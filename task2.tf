provider "aws" {
  region  = "ap-south-1"
  profile = "samarth"
}
resource "tls_private_key" "task-2-pri-key" { 
  algorithm   = "RSA"
  rsa_bits = "2048"
}

resource "aws_key_pair" "task-2-key" {
  depends_on = [ tls_private_key.task-2-pri-key, ]
  key_name   = "task-2-key"
  public_key = tls_private_key.task-2-pri-key.public_key_openssh
}

resource "aws_security_group" "task-2-sg" {
  depends_on = [ aws_key_pair.task-2-key, ]
  name        = "task-2-sg"
  description = "Allow SSH AND HTTP and NFS inbound traffic"
  vpc_id      = "vpc-758b931d"

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [ "0.0.0.0/0" ]
  }

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = [ "0.0.0.0/0" ]
  }
 ingress {
    description = "NFS"
    from_port   = 2049
    to_port     = 2049
    protocol    = "tcp"
    cidr_blocks = [ "0.0.0.0/0" ]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "task-2-sg"
  }
}


resource "aws_instance" "task-2-os1" {
   depends_on =  [ aws_key_pair.task-2-key,
              aws_security_group.task-2-sg, ] 
   ami                 = "ami-0447a12f28fddb066"
   instance_type = "t2.micro"
   key_name       =  "task-2-key"
   security_groups = [ "task-2-sg" ]
     connection {
     type     = "ssh"
     user     = "ec2-user"
     private_key = tls_private_key.task-2-pri-key.private_key_pem
     host     = aws_instance.task-2-os1.public_ip
   }
   provisioner "remote-exec" {
    inline = [
       "sudo yum update -y",
      "sudo yum install httpd  php git -y ",
      "sudo systemctl restart httpd",
      "sudo systemctl enable httpd",
    ]
  }
  tags = {
      Name =  "task-2-os1"
           }
}
resource "aws_efs_file_system" "allow_nfs" {
 depends_on =  [ aws_security_group.task-2-sg,
                aws_instance.task-2-os1,  ] 
  creation_token = "allow_nfs"

  tags = {
    Name = "allow_nfs"
  }
}

resource "aws_efs_mount_target" "alpha" {
 depends_on =  [ aws_efs_file_system.allow_nfs,
                         ] 
  file_system_id = aws_efs_file_system.allow_nfs.id
  subnet_id      = aws_instance.task-2-os1.subnet_id
  security_groups = ["${aws_security_group.task-2-sg.id}"]
}



resource "null_resource" "null-remote-1"  {
 depends_on = [ 
               aws_efs_mount_target.alpha,
                  ]
  connection {
    type     = "ssh"
    user     = "ec2-user"
    private_key = tls_private_key.task-2-pri-key.private_key_pem
    host     = aws_instance.task-2-os1.public_ip
  }
  provisioner "remote-exec" {
      inline = [
        "sudo echo ${aws_efs_file_system.allow_nfs.dns_name}:/var/www/html efs defaults,_netdev 0 0 >> sudo /etc/fstab",
        "sudo mount  ${aws_efs_file_system.allow_nfs.dns_name}:/  /var/www/html",
        "sudo curl https://https://github.com/samarth12pant/aws-tera-repo/blob/master/index.html > index.html",                                  "sudo cp index.html  /var/www/html/",
      ]
  }
}

resource "aws_s3_bucket" "terra-samarth" {
depends_on = [
    null_resource.null-remote-1,    
  ]     
  bucket = "terra-samarth"
  force_destroy = true
  acl    = "public-read"
  policy = <<POLICY
{
  "Version": "2012-10-17",
  "Id": "MYBUCKETPOLICY",
  "Statement": [
    {
      "Sid": "PublicReadGetObject",
      "Effect": "Allow",
      "Principal": "*",
      "Action": "s3:*",
      "Resource": "arn:aws:s3:::terra-samarth/*"
    }
  ]
}
POLICY
}
resource "aws_s3_bucket_object" "task-2-object" {
  depends_on = [ aws_s3_bucket.terra-samarth,
                null_resource.null-remote-1,
               
 ]
     bucket = aws_s3_bucket.terra-samarth.bucket
  key    = "one"
  source = "E:/U.P.E.S/RED_HAT_TRAINING/tera/myaws/task-2-EFS/IMG_20200121_090551-01.jpeg"
  etag = "E:/U.P.E.S/RED_HAT_TRAINING/tera/myaws/task-2-EFS/IMG_20200121_090551-01.jpeg"
  acl = "public-read"
  content_type = "image/jpeg"
}

locals {
  s3_origin_id = "aws_s3_bucket.terra-samarth.id"
}

resource "aws_cloudfront_origin_access_identity" "oai" {
   comment = "CloudFront S3 sync"
}
// Creating CloudFront Distribution for S3
resource "aws_cloudfront_distribution" "s3_distribution" {
  depends_on = [
    aws_key_pair.task-2-key,
    aws_instance.task-2-os1
  ] 
  origin {
    domain_name = aws_s3_bucket.terra-samarth.bucket_regional_domain_name
    origin_id   = local.s3_origin_id
    s3_origin_config {
      origin_access_identity = aws_cloudfront_origin_access_identity.oai.cloudfront_access_identity_path
    }
  }
  enabled             = true
  is_ipv6_enabled     = true
  comment             = "ClouFront S3 sync"
  default_cache_behavior {
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = local.s3_origin_id
    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }
    viewer_protocol_policy = "allow-all"
    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
  }
# Cache behavior with precedence 0
  ordered_cache_behavior {
    path_pattern     = "/content/immutable/*"
    allowed_methods  = ["GET", "HEAD", "OPTIONS"]
    cached_methods   = ["GET", "HEAD", "OPTIONS"]
    target_origin_id = local.s3_origin_id
    forwarded_values {
      query_string = false
      headers      = ["Origin"]
      cookies {
        forward = "none"
      }
    }
    min_ttl                = 0
    default_ttl            = 86400
    max_ttl                = 31536000
    compress               = true
    viewer_protocol_policy = "redirect-to-https"
  }
# Cache behavior with precedence 1
  ordered_cache_behavior {
    path_pattern     = "/content/*"
    allowed_methods  = ["GET", "HEAD", "OPTIONS"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = local.s3_origin_id
    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }
    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
    compress               = true
    viewer_protocol_policy = "redirect-to-https"
  }
  price_class = "PriceClass_200"
  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }
  tags = {
    Environment = "production"
  }
  viewer_certificate {
    cloudfront_default_certificate = true
  }
}
output "out3" {
        value = aws_cloudfront_distribution.s3_distribution.domain_name
}


resource "null_resource" "null-remote2" {
 depends_on = [ aws_cloudfront_distribution.s3_distribution, ]
  connection {
    type     = "ssh"
    user     = "ec2-user"
    private_key = tls_private_key.task-2-pri-key.private_key_pem
    host     = aws_instance.task-2-os1.public_ip
   }
   provisioner "remote-exec" {
      inline = [
      "sudo su << EOF",
      "echo \"<img src='https://${aws_cloudfront_distribution.s3_distribution.domain_name}/${aws_s3_bucket_object.task-2-object.key }'>\" >> /var/www/html/index.html",
       "EOF"
   ]
 }
}
resource "null_resource" "nulllocal3" {
  depends_on = [
      null_resource.null-remote2,
   ]
   provisioner "local-exec" {
         command = "start chrome ${aws_instance.task-2-os1.public_ip}/index.html"
    }
}