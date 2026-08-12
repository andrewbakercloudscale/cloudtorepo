# Auto-generated import blocks — do not edit by hand.
# Run: terraform plan -generate-config-out=generated.tf

import {
  to = aws_cloudwatch_event_rule.default_ec2statechanged
  id = "EC2StateChanged"
}

import {
  to = aws_cloudwatch_event_rule.default_spotinterrupt
  id = "SpotInterrupt"
}

import {
  to = aws_cloudwatch_event_rule.default_startvortex8_30
  id = "StartVortex8-30"
}

import {
  to = aws_cloudwatch_event_rule.default_mycloudwatcheventslamdba
  id = "myCloudWatchEventsLamdba"
}

