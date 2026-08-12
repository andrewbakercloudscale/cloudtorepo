# Auto-generated import blocks — do not edit by hand.
# Run: terraform plan -generate-config-out=generated.tf

import {
  to = aws_vpc.defaultvpc
  id = "vpc-0957b260"
}

import {
  to = aws_subnet.defaultvpcsubnetb
  id = "subnet-93d3d4eb"
}

import {
  to = aws_subnet.defaultvpcsubnetc
  id = "subnet-52557418"
}

import {
  to = aws_subnet.defaultvpcsubneta
  id = "subnet-b156b3d8"
}

import {
  to = aws_security_group.cloudflare_proxy
  id = "sg-02c2539d27ffe5a5f"
}

import {
  to = aws_security_group.launch_wizard_6
  id = "sg-011a26aef17beff13"
}

import {
  to = aws_security_group.launch_wizard_7
  id = "sg-024bd977787fb2789"
}

import {
  to = aws_route_table.defaultroutetable
  id = "rtb-6157b208"
}

import {
  to = aws_internet_gateway.defaultvpcigw
  id = "igw-5a56b333"
}

