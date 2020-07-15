provider "aws" {
	region = "ap-south-1"
	profile = "profile_task1"
}

resource "aws_security_group" "task2_security_group" {
	name = "task2_security_group"
	description = "Allow on port 80 and 22"

	ingress {
		description = "http on port 80"
		from_port = 80
		to_port = 80
		protocol = "tcp"
		cidr_blocks = ["0.0.0.0/0"]
	}

	ingress {
		description = "ssh on port 22"
		from_port = 22
		to_port = 22
		protocol = "tcp"
		cidr_blocks = ["0.0.0.0/0"]
	}

	ingress {
        description = "NFS on port 2049"
        from_port = 2049
        to_port = 2049
        protocol = "tcp"
        cidr_blocks = ["0.0.0.0/0"]
	}
	
	egress {
		from_port = 0
		to_port = 0
		protocol = "-1"
		cidr_blocks = ["0.0.0.0/0"]
	}
	
	lifecycle {
		create_before_destroy = true
	}

	tags = {
		Name = "task2_security_group"
	}
}

resource "aws_key_pair" "task2_keypair" {
	key_name = "task2_keypair"
	public_key = file("../task2_keypair.pub")
}

resource "aws_subnet" "task2_subnet" {
    vpc_id = aws_security_group.task2_security_group.vpc_id
    availability_zone = "ap-south-1a"
    cidr_block = "172.31.48.0/20"
}

resource "aws_efs_file_system" "task2_html_fs" {
	creation_token = "html-fs"
	tags = {
		Name = "HtmlFs"
	}
}

resource "aws_efs_mount_target" "task2_html_fs_mt" {
    file_system_id = aws_efs_file_system.task2_html_fs.id
    subnet_id = aws_subnet.task2_subnet.id
    security_groups = [aws_security_group.task2_security_group.id]
}

resource "aws_instance" "task2_main_instance" {
	ami = "ami-0447a12f28fddb066"
	instance_type = "t2.micro"
	availability_zone = "ap-south-1a"
	key_name = "task2_keypair"
	associate_public_ip_address = true
    vpc_security_group_ids = ["${aws_security_group.task2_security_group.id}"]
    subnet_id = aws_subnet.task2_subnet.id
    tags = {
        Name = "task2_main_instance"
    }
    
    user_data = <<-EOF
			#!/bin/bash
			#cloud-config
			repo_update: true
			repo_upgrade: all
			sudo yum install git httpd amazon-efs-utils nfs-utils -y
			sudo systemctl --now enable httpd
			files_system_id_1="${aws_efs_file_system.task2_html_fs.id}"
			efs_mount_point_1="/var/www/html"
			mkdir -p "$efs_mount_point_1"
			test -f "/sbin/monut.efs" && echo "$file_system_id_1:/$efs_mount_point_1 efs tls._netdev" >> /etc/fstab || echo "$file_system_id_1.efs.ap-south-1.amazonaws.com:/ $efs_mount_point_1 nfs4 nfsvers=4.1,rsize=1048576,wsize=1048576,hard,timeo=600,retrans=2,noresvport,_netdev 0 0" >> /etc/fstab
			test -f "/sbin/mount.efs" && echo -e "\n[client-info]\nsource=liw" >> /etc/amazon/efs/efs-utils.conf
			mount -a -t efs,nfs4 defaults
	EOF
}

resource "null_resource" "nullremote" {
    depends_on = [aws_instance.task2_main_instance]

    connection {
		type = "ssh"
		host = aws_instance.task2_main_instance.public_ip
		user = "ec2-user"
		private_key = file("../task2_keypair")
	}

	provisioner "remote-exec" {
		inline = [
            "sudo crontab -l > cronconfig.txt",
			"sudo echo \"* * * * * sudo wget https://raw.githubusercontent.com/arun5309/lwi-hmc-task2/master/html/index.html -O /var/www/html/index.html\" >> cronconfig.txt", 
			"cat cronconfig.txt | sudo crontab -" 
		]
	}
}

resource "aws_s3_bucket" "task2-image-bucket" {
	bucket = "task2-image-bucket"
	acl = "public-read"
	tags = {
		Name = "task2-image-bucket"
	}
}

locals {
    img_path = "../image.png"
}

# Create s3 bucket object

resource "aws_s3_bucket_object" "object" {
  bucket = "task2-image-bucket"
  key    = "image.png"
  source = local.img_path
  etag = filemd5(local.img_path)
  acl = "public-read"
}


locals {
	s3_origin_id = "s3-origin"
}

resource "aws_cloudfront_distribution" "task2-s3-distribution" {
	enabled = true
	is_ipv6_enabled = true
	
	origin {
		domain_name = aws_s3_bucket.task2-image-bucket.bucket_regional_domain_name
		origin_id = local.s3_origin_id
	}

	restrictions {
		geo_restriction {
			restriction_type = "none"
		}
	}

	default_cache_behavior {
		target_origin_id = local.s3_origin_id
		allowed_methods = ["HEAD", "DELETE", "POST", "GET", "OPTIONS", "PUT", "PATCH"]
    	cached_methods  = ["HEAD", "GET", "OPTIONS"]

    	forwarded_values {
      		query_string = false
      		cookies {
        		forward = "none"
      		}
		}

		viewer_protocol_policy = "redirect-to-https"
    	min_ttl                = 0
    	default_ttl            = 720
    	max_ttl                = 86400
	}

	viewer_certificate {
    	cloudfront_default_certificate = true
  	}
}
