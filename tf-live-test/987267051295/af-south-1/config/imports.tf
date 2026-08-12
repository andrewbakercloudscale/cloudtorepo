# Auto-generated import blocks — do not edit by hand.
# Run: terraform plan -generate-config-out=generated.tf

import {
  to = aws_config_configuration_recorder.default
  id = "default"
}

import {
  to = aws_config_configuration_recorder_status.default
  id = "default"
}

import {
  to = aws_config_delivery_channel.default
  id = "default"
}

import {
  to = aws_config_config_rule.account_part_of_organizations
  id = "account-part-of-organizations"
}

import {
  to = aws_config_config_rule.cloudtrail_enabled
  id = "cloudtrail-enabled"
}

import {
  to = aws_config_config_rule.cloudtrail_security_trail_enabled
  id = "cloudtrail-security-trail-enabled"
}

import {
  to = aws_config_config_rule.ec2_security_group_attached_to_eni
  id = "ec2-security-group-attached-to-eni"
}

import {
  to = aws_config_config_rule.securityhub_access_keys_rotated_774aa6c9
  id = "securityhub-access-keys-rotated-774aa6c9"
}

import {
  to = aws_config_config_rule.securityhub_acm_certificate_expiration_check_e2df179f
  id = "securityhub-acm-certificate-expiration-check-e2df179f"
}

import {
  to = aws_config_config_rule.securityhub_acm_certificate_rsa_check_383f707d
  id = "securityhub-acm-certificate-rsa-check-383f707d"
}

import {
  to = aws_config_config_rule.securityhub_acm_pca_root_ca_disabled_33b9d80b
  id = "securityhub-acm-pca-root-ca-disabled-33b9d80b"
}

import {
  to = aws_config_config_rule.securityhub_alb_desync_mode_check_0e7d0df3
  id = "securityhub-alb-desync-mode-check-0e7d0df3"
}

import {
  to = aws_config_config_rule.securityhub_alb_http_drop_invalid_header_enabled_69a3900a
  id = "securityhub-alb-http-drop-invalid-header-enabled-69a3900a"
}

import {
  to = aws_config_config_rule.securityhub_alb_http_to_https_redirection_check_9eb976ce
  id = "securityhub-alb-http-to-https-redirection-check-9eb976ce"
}

import {
  to = aws_config_config_rule.securityhub_api_gw_associated_with_waf_035510a9
  id = "securityhub-api-gw-associated-with-waf-035510a9"
}

import {
  to = aws_config_config_rule.securityhub_api_gw_cache_encrypted_fc0a58cd
  id = "securityhub-api-gw-cache-encrypted-fc0a58cd"
}

import {
  to = aws_config_config_rule.securityhub_api_gw_execution_logging_enabled_09bb5f73
  id = "securityhub-api-gw-execution-logging-enabled-09bb5f73"
}

import {
  to = aws_config_config_rule.securityhub_api_gw_ssl_enabled_1ab44c4c
  id = "securityhub-api-gw-ssl-enabled-1ab44c4c"
}

import {
  to = aws_config_config_rule.securityhub_api_gw_xray_enabled_dc31fd7a
  id = "securityhub-api-gw-xray-enabled-dc31fd7a"
}

import {
  to = aws_config_config_rule.securityhub_api_gwv2_access_logs_enabled_fcfebbe4
  id = "securityhub-api-gwv2-access-logs-enabled-fcfebbe4"
}

import {
  to = aws_config_config_rule.securityhub_api_gwv2_authorization_type_configured_93253d61
  id = "securityhub-api-gwv2-authorization-type-configured-93253d61"
}

import {
  to = aws_config_config_rule.securityhub_apigatewayv2_integration_private_https_enabled_f7203c64
  id = "securityhub-apigatewayv2-integration-private-https-enabled-f7203c64"
}

import {
  to = aws_config_config_rule.securityhub_appsync_authorization_check_94118ac3
  id = "securityhub-appsync-authorization-check-94118ac3"
}

import {
  to = aws_config_config_rule.securityhub_appsync_logging_enabled_e4ff932a
  id = "securityhub-appsync-logging-enabled-e4ff932a"
}

import {
  to = aws_config_config_rule.securityhub_athena_workgroup_logging_enabled_e7740166
  id = "securityhub-athena-workgroup-logging-enabled-e7740166"
}

import {
  to = aws_config_config_rule.securityhub_aurora_mysql_cluster_audit_logging_bbda887d
  id = "securityhub-aurora-mysql-cluster-audit-logging-bbda887d"
}

import {
  to = aws_config_config_rule.securityhub_autoscaling_group_elb_healthcheck_required_17d48b72
  id = "securityhub-autoscaling-group-elb-healthcheck-required-17d48b72"
}

import {
  to = aws_config_config_rule.securityhub_autoscaling_launch_config_public_ip_disabled_425834c7
  id = "securityhub-autoscaling-launch-config-public-ip-disabled-425834c7"
}

import {
  to = aws_config_config_rule.securityhub_autoscaling_launch_template_2f1ad2a5
  id = "securityhub-autoscaling-launch-template-2f1ad2a5"
}

import {
  to = aws_config_config_rule.securityhub_autoscaling_launchconfig_requires_imdsv2_ec43f147
  id = "securityhub-autoscaling-launchconfig-requires-imdsv2-ec43f147"
}

import {
  to = aws_config_config_rule.securityhub_autoscaling_multiple_az_ec0ef640
  id = "securityhub-autoscaling-multiple-az-ec0ef640"
}

import {
  to = aws_config_config_rule.securityhub_autoscaling_multiple_instance_types_5d6c4874
  id = "securityhub-autoscaling-multiple-instance-types-5d6c4874"
}

import {
  to = aws_config_config_rule.securityhub_backup_recovery_point_encrypted_1514952e
  id = "securityhub-backup-recovery-point-encrypted-1514952e"
}

import {
  to = aws_config_config_rule.securityhub_beanstalk_enhanced_health_reporting_enabled_d33ac9a4
  id = "securityhub-beanstalk-enhanced-health-reporting-enabled-d33ac9a4"
}

import {
  to = aws_config_config_rule.securityhub_clb_desync_mode_check_585c14b4
  id = "securityhub-clb-desync-mode-check-585c14b4"
}

import {
  to = aws_config_config_rule.securityhub_clb_multiple_az_8cc5fc29
  id = "securityhub-clb-multiple-az-8cc5fc29"
}

import {
  to = aws_config_config_rule.securityhub_cloud_trail_cloud_watch_logs_enabled_3733030e
  id = "securityhub-cloud-trail-cloud-watch-logs-enabled-3733030e"
}

import {
  to = aws_config_config_rule.securityhub_cloud_trail_encryption_enabled_04a14217
  id = "securityhub-cloud-trail-encryption-enabled-04a14217"
}

import {
  to = aws_config_config_rule.securityhub_cloud_trail_log_file_validation_enabled_0af538a9
  id = "securityhub-cloud-trail-log-file-validation-enabled-0af538a9"
}

import {
  to = aws_config_config_rule.securityhub_cloudformation_stack_service_role_check_f184aceb
  id = "securityhub-cloudformation-stack-service-role-check-f184aceb"
}

import {
  to = aws_config_config_rule.securityhub_cloudformation_termination_protection_check_b874d3da
  id = "securityhub-cloudformation-termination-protection-check-b874d3da"
}

import {
  to = aws_config_config_rule.securityhub_cmk_backing_key_rotation_enabled_912506e4
  id = "securityhub-cmk-backing-key-rotation-enabled-912506e4"
}

import {
  to = aws_config_config_rule.securityhub_codebuild_project_envvar_awscred_check_fd4cc9fd
  id = "securityhub-codebuild-project-envvar-awscred-check-fd4cc9fd"
}

import {
  to = aws_config_config_rule.securityhub_codebuild_project_logging_enabled_7c524c5f
  id = "securityhub-codebuild-project-logging-enabled-7c524c5f"
}

import {
  to = aws_config_config_rule.securityhub_codebuild_project_s3_logs_encrypted_65037823
  id = "securityhub-codebuild-project-s3-logs-encrypted-65037823"
}

import {
  to = aws_config_config_rule.securityhub_codebuild_project_source_repo_url_check_634f4fe3
  id = "securityhub-codebuild-project-source-repo-url-check-634f4fe3"
}

import {
  to = aws_config_config_rule.securityhub_codebuild_report_group_encrypted_at_rest_80e7d4db
  id = "securityhub-codebuild-report-group-encrypted-at-rest-80e7d4db"
}

import {
  to = aws_config_config_rule.securityhub_cognito_identity_pool_unauth_access_check_105a7237
  id = "securityhub-cognito-identity-pool-unauth-access-check-105a7237"
}

import {
  to = aws_config_config_rule.securityhub_cognito_user_pool_deletion_protection_enabled_79902d09
  id = "securityhub-cognito-user-pool-deletion-protection-enabled-79902d09"
}

import {
  to = aws_config_config_rule.securityhub_cognito_user_pool_mfa_enabled_96631858
  id = "securityhub-cognito-user-pool-mfa-enabled-96631858"
}

import {
  to = aws_config_config_rule.securityhub_cognito_user_pool_password_policy_check_f11f7585
  id = "securityhub-cognito-user-pool-password-policy-check-f11f7585"
}

import {
  to = aws_config_config_rule.securityhub_cognito_userpool_cust_auth_threat_full_check_3c4da202
  id = "securityhub-cognito-userpool-cust-auth-threat-full-check-3c4da202"
}

import {
  to = aws_config_config_rule.securityhub_connect_instance_logging_enabled_517cc58a
  id = "securityhub-connect-instance-logging-enabled-517cc58a"
}

import {
  to = aws_config_config_rule.securityhub_custom_eventbus_policy_attached_6cb2ea7e
  id = "securityhub-custom-eventbus-policy-attached-6cb2ea7e"
}

import {
  to = aws_config_config_rule.securityhub_datasync_task_logging_enabled_8767c79d
  id = "securityhub-datasync-task-logging-enabled-8767c79d"
}

import {
  to = aws_config_config_rule.securityhub_db_instance_backup_enabled_f7193f10
  id = "securityhub-db-instance-backup-enabled-f7193f10"
}

import {
  to = aws_config_config_rule.securityhub_dms_auto_minor_version_upgrade_check_7d8a50d2
  id = "securityhub-dms-auto-minor-version-upgrade-check-7d8a50d2"
}

import {
  to = aws_config_config_rule.securityhub_dms_endpoint_ssl_configured_dc0108bd
  id = "securityhub-dms-endpoint-ssl-configured-dc0108bd"
}

import {
  to = aws_config_config_rule.securityhub_dms_mongo_db_authentication_enabled_99ef788b
  id = "securityhub-dms-mongo-db-authentication-enabled-99ef788b"
}

import {
  to = aws_config_config_rule.securityhub_dms_redis_tls_enabled_e989b34b
  id = "securityhub-dms-redis-tls-enabled-e989b34b"
}

import {
  to = aws_config_config_rule.securityhub_dms_replication_instance_multi_az_enabled_e0a9dcc5
  id = "securityhub-dms-replication-instance-multi-az-enabled-e0a9dcc5"
}

import {
  to = aws_config_config_rule.securityhub_dms_replication_not_public_870758d3
  id = "securityhub-dms-replication-not-public-870758d3"
}

import {
  to = aws_config_config_rule.securityhub_dms_replication_task_sourcedb_logging_7e5f58a0
  id = "securityhub-dms-replication-task-sourcedb-logging-7e5f58a0"
}

import {
  to = aws_config_config_rule.securityhub_dms_replication_task_targetdb_logging_8ae3ed21
  id = "securityhub-dms-replication-task-targetdb-logging-8ae3ed21"
}

import {
  to = aws_config_config_rule.securityhub_dynamodb_autoscaling_enabled_840efbe1
  id = "securityhub-dynamodb-autoscaling-enabled-840efbe1"
}

import {
  to = aws_config_config_rule.securityhub_dynamodb_pitr_enabled_6d48a58d
  id = "securityhub-dynamodb-pitr-enabled-6d48a58d"
}

import {
  to = aws_config_config_rule.securityhub_dynamodb_table_deletion_protection_enabled_cc10289e
  id = "securityhub-dynamodb-table-deletion-protection-enabled-cc10289e"
}

import {
  to = aws_config_config_rule.securityhub_ebs_snapshot_block_public_access_b68b6dd7
  id = "securityhub-ebs-snapshot-block-public-access-b68b6dd7"
}

import {
  to = aws_config_config_rule.securityhub_ebs_snapshot_public_restorable_check_54d7c5d8
  id = "securityhub-ebs-snapshot-public-restorable-check-54d7c5d8"
}

import {
  to = aws_config_config_rule.securityhub_ec2_client_vpn_connection_log_enabled_c24c040b
  id = "securityhub-ec2-client-vpn-connection-log-enabled-c24c040b"
}

import {
  to = aws_config_config_rule.securityhub_ec2_ebs_encryption_by_default_4d352b12
  id = "securityhub-ec2-ebs-encryption-by-default-4d352b12"
}

import {
  to = aws_config_config_rule.securityhub_ec2_enis_source_destination_check_enabled_0deac96e
  id = "securityhub-ec2-enis-source-destination-check-enabled-0deac96e"
}

import {
  to = aws_config_config_rule.securityhub_ec2_imdsv2_check_a97e889b
  id = "securityhub-ec2-imdsv2-check-a97e889b"
}

import {
  to = aws_config_config_rule.securityhub_ec2_instance_managed_by_ssm_04cbcf73
  id = "securityhub-ec2-instance-managed-by-ssm-04cbcf73"
}

import {
  to = aws_config_config_rule.securityhub_ec2_instance_multiple_eni_check_2b7082d8
  id = "securityhub-ec2-instance-multiple-eni-check-2b7082d8"
}

import {
  to = aws_config_config_rule.securityhub_ec2_instance_no_public_ip_269d5cd0
  id = "securityhub-ec2-instance-no-public-ip-269d5cd0"
}

import {
  to = aws_config_config_rule.securityhub_ec2_launch_template_imdsv2_check_6b723f4e
  id = "securityhub-ec2-launch-template-imdsv2-check-6b723f4e"
}

import {
  to = aws_config_config_rule.securityhub_ec2_launch_template_public_ip_disabled_97078948
  id = "securityhub-ec2-launch-template-public-ip-disabled-97078948"
}

import {
  to = aws_config_config_rule.securityhub_ec2_launch_templates_ebs_volume_encrypted_a9dda2cf
  id = "securityhub-ec2-launch-templates-ebs-volume-encrypted-a9dda2cf"
}

import {
  to = aws_config_config_rule.securityhub_ec2_managedinstance_association_compliance_status_check_0592df4b
  id = "securityhub-ec2-managedinstance-association-compliance-status-check-0592df4b"
}

import {
  to = aws_config_config_rule.securityhub_ec2_managedinstance_patch_compliance_310ff521
  id = "securityhub-ec2-managedinstance-patch-compliance-310ff521"
}

import {
  to = aws_config_config_rule.securityhub_ec2_transit_gateway_auto_vpc_attach_disabled_85ad5149
  id = "securityhub-ec2-transit-gateway-auto-vpc-attach-disabled-85ad5149"
}

import {
  to = aws_config_config_rule.securityhub_ec2_vpc_bpa_internet_gateway_blocked_4b22b308
  id = "securityhub-ec2-vpc-bpa-internet-gateway-blocked-4b22b308"
}

import {
  to = aws_config_config_rule.securityhub_ec2_vpn_connection_logging_enabled_10c4136e
  id = "securityhub-ec2-vpn-connection-logging-enabled-10c4136e"
}

import {
  to = aws_config_config_rule.securityhub_ecr_private_image_scanning_enabled_80ed8cc4
  id = "securityhub-ecr-private-image-scanning-enabled-80ed8cc4"
}

import {
  to = aws_config_config_rule.securityhub_ecr_private_lifecycle_policy_configured_a96e8461
  id = "securityhub-ecr-private-lifecycle-policy-configured-a96e8461"
}

import {
  to = aws_config_config_rule.securityhub_ecr_private_tag_immutability_enabled_8fd5671d
  id = "securityhub-ecr-private-tag-immutability-enabled-8fd5671d"
}

import {
  to = aws_config_config_rule.securityhub_ecs_capacity_provider_termination_check_fa461790
  id = "securityhub-ecs-capacity-provider-termination-check-fa461790"
}

import {
  to = aws_config_config_rule.securityhub_ecs_container_insights_enabled_cc670288
  id = "securityhub-ecs-container-insights-enabled-cc670288"
}

import {
  to = aws_config_config_rule.securityhub_ecs_containers_nonprivileged_092dd336
  id = "securityhub-ecs-containers-nonprivileged-092dd336"
}

import {
  to = aws_config_config_rule.securityhub_ecs_containers_readonly_access_57a8ddf5
  id = "securityhub-ecs-containers-readonly-access-57a8ddf5"
}

import {
  to = aws_config_config_rule.securityhub_ecs_fargate_latest_platform_version_307dfd33
  id = "securityhub-ecs-fargate-latest-platform-version-307dfd33"
}

import {
  to = aws_config_config_rule.securityhub_ecs_no_environment_secrets_62e07dba
  id = "securityhub-ecs-no-environment-secrets-62e07dba"
}

import {
  to = aws_config_config_rule.securityhub_ecs_service_assign_public_ip_disabled_5765fd14
  id = "securityhub-ecs-service-assign-public-ip-disabled-5765fd14"
}

import {
  to = aws_config_config_rule.securityhub_ecs_task_definition_efs_encryption_enabled_1152f368
  id = "securityhub-ecs-task-definition-efs-encryption-enabled-1152f368"
}

import {
  to = aws_config_config_rule.securityhub_ecs_task_definition_linux_user_non_root_2dc8b28b
  id = "securityhub-ecs-task-definition-linux-user-non-root-2dc8b28b"
}

import {
  to = aws_config_config_rule.securityhub_ecs_task_definition_log_configuration_5346ead2
  id = "securityhub-ecs-task-definition-log-configuration-5346ead2"
}

import {
  to = aws_config_config_rule.securityhub_ecs_task_definition_pid_mode_check_8e88353a
  id = "securityhub-ecs-task-definition-pid-mode-check-8e88353a"
}

import {
  to = aws_config_config_rule.securityhub_ecs_task_definition_windows_user_non_admin_5624b77a
  id = "securityhub-ecs-task-definition-windows-user-non-admin-5624b77a"
}

import {
  to = aws_config_config_rule.securityhub_ecs_taskset_assign_public_ip_disabled_c2254dfd
  id = "securityhub-ecs-taskset-assign-public-ip-disabled-c2254dfd"
}

import {
  to = aws_config_config_rule.securityhub_efs_access_point_enforce_root_directory_abe0a9c4
  id = "securityhub-efs-access-point-enforce-root-directory-abe0a9c4"
}

import {
  to = aws_config_config_rule.securityhub_efs_access_point_enforce_user_identity_5bec47f9
  id = "securityhub-efs-access-point-enforce-user-identity-5bec47f9"
}

import {
  to = aws_config_config_rule.securityhub_efs_automatic_backups_enabled_b9d3e723
  id = "securityhub-efs-automatic-backups-enabled-b9d3e723"
}

import {
  to = aws_config_config_rule.securityhub_efs_encrypted_check_c4673af5
  id = "securityhub-efs-encrypted-check-c4673af5"
}

import {
  to = aws_config_config_rule.securityhub_efs_filesystem_ct_encrypted_baca3ac1
  id = "securityhub-efs-filesystem-ct-encrypted-baca3ac1"
}

import {
  to = aws_config_config_rule.securityhub_efs_in_backup_plan_272a281a
  id = "securityhub-efs-in-backup-plan-272a281a"
}

import {
  to = aws_config_config_rule.securityhub_efs_mount_target_public_accessible_c974e5ec
  id = "securityhub-efs-mount-target-public-accessible-c974e5ec"
}

import {
  to = aws_config_config_rule.securityhub_eks_cluster_log_enabled_922f94cc
  id = "securityhub-eks-cluster-log-enabled-922f94cc"
}

import {
  to = aws_config_config_rule.securityhub_eks_cluster_secrets_encrypted_fac5c9f1
  id = "securityhub-eks-cluster-secrets-encrypted-fac5c9f1"
}

import {
  to = aws_config_config_rule.securityhub_eks_cluster_supported_version_f1abc0a7
  id = "securityhub-eks-cluster-supported-version-f1abc0a7"
}

import {
  to = aws_config_config_rule.securityhub_eks_endpoint_no_public_access_7f93f7b4
  id = "securityhub-eks-endpoint-no-public-access-7f93f7b4"
}

import {
  to = aws_config_config_rule.securityhub_elastic_beanstalk_logs_to_cloudwatch_9225ec61
  id = "securityhub-elastic-beanstalk-logs-to-cloudwatch-9225ec61"
}

import {
  to = aws_config_config_rule.securityhub_elastic_beanstalk_managed_updates_enabled_18001d6a
  id = "securityhub-elastic-beanstalk-managed-updates-enabled-18001d6a"
}

import {
  to = aws_config_config_rule.securityhub_elasticache_auto_minor_version_upgrade_check_e1a70454
  id = "securityhub-elasticache-auto-minor-version-upgrade-check-e1a70454"
}

import {
  to = aws_config_config_rule.securityhub_elasticache_redis_cluster_automatic_backup_check_0a9765f2
  id = "securityhub-elasticache-redis-cluster-automatic-backup-check-0a9765f2"
}

import {
  to = aws_config_config_rule.securityhub_elasticache_repl_grp_auto_failover_enabled_83fddbaa
  id = "securityhub-elasticache-repl-grp-auto-failover-enabled-83fddbaa"
}

import {
  to = aws_config_config_rule.securityhub_elasticache_repl_grp_encrypted_at_rest_ee6e37d2
  id = "securityhub-elasticache-repl-grp-encrypted-at-rest-ee6e37d2"
}

import {
  to = aws_config_config_rule.securityhub_elasticache_repl_grp_encrypted_in_transit_4e395de6
  id = "securityhub-elasticache-repl-grp-encrypted-in-transit-4e395de6"
}

import {
  to = aws_config_config_rule.securityhub_elasticache_repl_grp_redis_auth_enabled_83545a24
  id = "securityhub-elasticache-repl-grp-redis-auth-enabled-83545a24"
}

import {
  to = aws_config_config_rule.securityhub_elasticache_subnet_group_check_b60dd71d
  id = "securityhub-elasticache-subnet-group-check-b60dd71d"
}

import {
  to = aws_config_config_rule.securityhub_elasticsearch_audit_logging_enabled_272fb20c
  id = "securityhub-elasticsearch-audit-logging-enabled-272fb20c"
}

import {
  to = aws_config_config_rule.securityhub_elasticsearch_data_node_fault_tolerance_c828ee99
  id = "securityhub-elasticsearch-data-node-fault-tolerance-c828ee99"
}

import {
  to = aws_config_config_rule.securityhub_elasticsearch_encrypted_at_rest_2958fcab
  id = "securityhub-elasticsearch-encrypted-at-rest-2958fcab"
}

import {
  to = aws_config_config_rule.securityhub_elasticsearch_https_required_c3f868d7
  id = "securityhub-elasticsearch-https-required-c3f868d7"
}

import {
  to = aws_config_config_rule.securityhub_elasticsearch_in_vpc_only_906f985d
  id = "securityhub-elasticsearch-in-vpc-only-906f985d"
}

import {
  to = aws_config_config_rule.securityhub_elasticsearch_logs_to_cloudwatch_431feb80
  id = "securityhub-elasticsearch-logs-to-cloudwatch-431feb80"
}

import {
  to = aws_config_config_rule.securityhub_elasticsearch_primary_node_fault_tolerance_bd83fcba
  id = "securityhub-elasticsearch-primary-node-fault-tolerance-bd83fcba"
}

import {
  to = aws_config_config_rule.securityhub_elb_connection_draining_enabled_40ba7f17
  id = "securityhub-elb-connection-draining-enabled-40ba7f17"
}

import {
  to = aws_config_config_rule.securityhub_elb_cross_zone_load_balancing_enabled_ff0d16c8
  id = "securityhub-elb-cross-zone-load-balancing-enabled-ff0d16c8"
}

import {
  to = aws_config_config_rule.securityhub_elb_deletion_protection_enabled_0938a456
  id = "securityhub-elb-deletion-protection-enabled-0938a456"
}

import {
  to = aws_config_config_rule.securityhub_elb_logging_enabled_44f229db
  id = "securityhub-elb-logging-enabled-44f229db"
}

import {
  to = aws_config_config_rule.securityhub_elb_predefined_security_policy_ssl_check_14fdea58
  id = "securityhub-elb-predefined-security-policy-ssl-check-14fdea58"
}

import {
  to = aws_config_config_rule.securityhub_elb_tls_https_listeners_only_332d83a3
  id = "securityhub-elb-tls-https-listeners-only-332d83a3"
}

import {
  to = aws_config_config_rule.securityhub_elbv2_listener_encryption_in_transit_a77b2558
  id = "securityhub-elbv2-listener-encryption-in-transit-a77b2558"
}

import {
  to = aws_config_config_rule.securityhub_elbv2_multiple_az_f39514a8
  id = "securityhub-elbv2-multiple-az-f39514a8"
}

import {
  to = aws_config_config_rule.securityhub_elbv2_predefined_security_policy_ssl_check_a956e4d6
  id = "securityhub-elbv2-predefined-security-policy-ssl-check-a956e4d6"
}

import {
  to = aws_config_config_rule.securityhub_elbv2_targetgroup_healthcheck_protocol_encrypted_8ce87dfa
  id = "securityhub-elbv2-targetgroup-healthcheck-protocol-encrypted-8ce87dfa"
}

import {
  to = aws_config_config_rule.securityhub_elbv2_targetgroup_protocol_encrypted_83a449b1
  id = "securityhub-elbv2-targetgroup-protocol-encrypted-83a449b1"
}

import {
  to = aws_config_config_rule.securityhub_emr_block_public_access_6c94cbdf
  id = "securityhub-emr-block-public-access-6c94cbdf"
}

import {
  to = aws_config_config_rule.securityhub_emr_master_no_public_ip_c8beb838
  id = "securityhub-emr-master-no-public-ip-c8beb838"
}

import {
  to = aws_config_config_rule.securityhub_emr_security_configuration_encryption_rest_48be0c5c
  id = "securityhub-emr-security-configuration-encryption-rest-48be0c5c"
}

import {
  to = aws_config_config_rule.securityhub_emr_security_configuration_encryption_transit_707c284a
  id = "securityhub-emr-security-configuration-encryption-transit-707c284a"
}

import {
  to = aws_config_config_rule.securityhub_encrypted_volumes_5c47ec73
  id = "securityhub-encrypted-volumes-5c47ec73"
}

import {
  to = aws_config_config_rule.securityhub_fsx_lustre_copy_tags_to_backups_39fdb1aa
  id = "securityhub-fsx-lustre-copy-tags-to-backups-39fdb1aa"
}

import {
  to = aws_config_config_rule.securityhub_fsx_ontap_deployment_type_check_878e2154
  id = "securityhub-fsx-ontap-deployment-type-check-878e2154"
}

import {
  to = aws_config_config_rule.securityhub_fsx_openzfs_copy_tags_enabled_af625a33
  id = "securityhub-fsx-openzfs-copy-tags-enabled-af625a33"
}

import {
  to = aws_config_config_rule.securityhub_fsx_openzfs_deployment_type_check_e40b5ece
  id = "securityhub-fsx-openzfs-deployment-type-check-e40b5ece"
}

import {
  to = aws_config_config_rule.securityhub_fsx_windows_deployment_type_check_739cf461
  id = "securityhub-fsx-windows-deployment-type-check-739cf461"
}

import {
  to = aws_config_config_rule.securityhub_glue_ml_transform_encrypted_at_rest_14a223c8
  id = "securityhub-glue-ml-transform-encrypted-at-rest-14a223c8"
}

import {
  to = aws_config_config_rule.securityhub_glue_spark_job_supported_version_235567bb
  id = "securityhub-glue-spark-job-supported-version-235567bb"
}

import {
  to = aws_config_config_rule.securityhub_guardduty_ec2_protection_runtime_enabled_5732378e
  id = "securityhub-guardduty-ec2-protection-runtime-enabled-5732378e"
}

import {
  to = aws_config_config_rule.securityhub_guardduty_ecs_protection_runtime_enabled_98b8af2b
  id = "securityhub-guardduty-ecs-protection-runtime-enabled-98b8af2b"
}

import {
  to = aws_config_config_rule.securityhub_guardduty_eks_protection_audit_enabled_d9093f63
  id = "securityhub-guardduty-eks-protection-audit-enabled-d9093f63"
}

import {
  to = aws_config_config_rule.securityhub_guardduty_eks_protection_runtime_enabled_3192c36e
  id = "securityhub-guardduty-eks-protection-runtime-enabled-3192c36e"
}

import {
  to = aws_config_config_rule.securityhub_guardduty_enabled_centralized_17f8f4c8
  id = "securityhub-guardduty-enabled-centralized-17f8f4c8"
}

import {
  to = aws_config_config_rule.securityhub_guardduty_lambda_protection_enabled_e824e79a
  id = "securityhub-guardduty-lambda-protection-enabled-e824e79a"
}

import {
  to = aws_config_config_rule.securityhub_guardduty_malware_protection_enabled_38d3d9bc
  id = "securityhub-guardduty-malware-protection-enabled-38d3d9bc"
}

import {
  to = aws_config_config_rule.securityhub_guardduty_rds_protection_enabled_868c59ef
  id = "securityhub-guardduty-rds-protection-enabled-868c59ef"
}

import {
  to = aws_config_config_rule.securityhub_guardduty_runtime_monitoring_enabled_0cf2c4d8
  id = "securityhub-guardduty-runtime-monitoring-enabled-0cf2c4d8"
}

import {
  to = aws_config_config_rule.securityhub_guardduty_s3_protection_enabled_9a4c526b
  id = "securityhub-guardduty-s3-protection-enabled-9a4c526b"
}

import {
  to = aws_config_config_rule.securityhub_iam_customer_policy_blocked_kms_actions_f58ec0a6
  id = "securityhub-iam-customer-policy-blocked-kms-actions-f58ec0a6"
}

import {
  to = aws_config_config_rule.securityhub_iam_inline_policy_blocked_kms_actions_f469c416
  id = "securityhub-iam-inline-policy-blocked-kms-actions-f469c416"
}

import {
  to = aws_config_config_rule.securityhub_iam_password_policy_ensure_expires_df4a1475
  id = "securityhub-iam-password-policy-ensure-expires-df4a1475"
}

import {
  to = aws_config_config_rule.securityhub_iam_password_policy_lowercase_letter_check_acdd215a
  id = "securityhub-iam-password-policy-lowercase-letter-check-acdd215a"
}

import {
  to = aws_config_config_rule.securityhub_iam_password_policy_minimum_length_check_944f846a
  id = "securityhub-iam-password-policy-minimum-length-check-944f846a"
}

import {
  to = aws_config_config_rule.securityhub_iam_password_policy_number_check_d62fb361
  id = "securityhub-iam-password-policy-number-check-d62fb361"
}

import {
  to = aws_config_config_rule.securityhub_iam_password_policy_prevent_reuse_check_40ed51c5
  id = "securityhub-iam-password-policy-prevent-reuse-check-40ed51c5"
}

import {
  to = aws_config_config_rule.securityhub_iam_password_policy_recommended_defaults_05398b0d
  id = "securityhub-iam-password-policy-recommended-defaults-05398b0d"
}

import {
  to = aws_config_config_rule.securityhub_iam_password_policy_symbol_check_74152c48
  id = "securityhub-iam-password-policy-symbol-check-74152c48"
}

import {
  to = aws_config_config_rule.securityhub_iam_password_policy_uppercase_letter_check_3d2e0c96
  id = "securityhub-iam-password-policy-uppercase-letter-check-3d2e0c96"
}

import {
  to = aws_config_config_rule.securityhub_iam_policy_no_statements_with_admin_access_a737484e
  id = "securityhub-iam-policy-no-statements-with-admin-access-a737484e"
}

import {
  to = aws_config_config_rule.securityhub_iam_policy_no_statements_with_full_access_fd021915
  id = "securityhub-iam-policy-no-statements-with-full-access-fd021915"
}

import {
  to = aws_config_config_rule.securityhub_iam_root_access_key_check_eb277cf8
  id = "securityhub-iam-root-access-key-check-eb277cf8"
}

import {
  to = aws_config_config_rule.securityhub_iam_user_no_policies_check_68267943
  id = "securityhub-iam-user-no-policies-check-68267943"
}

import {
  to = aws_config_config_rule.securityhub_iam_user_unused_credentials_check_f6ed027d
  id = "securityhub-iam-user-unused-credentials-check-f6ed027d"
}

import {
  to = aws_config_config_rule.securityhub_inspector_ec2_scan_enabled_45593f67
  id = "securityhub-inspector-ec2-scan-enabled-45593f67"
}

import {
  to = aws_config_config_rule.securityhub_inspector_ecr_scan_enabled_27824881
  id = "securityhub-inspector-ecr-scan-enabled-27824881"
}

import {
  to = aws_config_config_rule.securityhub_inspector_lambda_standard_scan_enabled_8addb810
  id = "securityhub-inspector-lambda-standard-scan-enabled-8addb810"
}

import {
  to = aws_config_config_rule.securityhub_kinesis_firehose_delivery_stream_encrypted_6c06a2ce
  id = "securityhub-kinesis-firehose-delivery-stream-encrypted-6c06a2ce"
}

import {
  to = aws_config_config_rule.securityhub_kinesis_stream_backup_retention_check_c97f9f2e
  id = "securityhub-kinesis-stream-backup-retention-check-c97f9f2e"
}

import {
  to = aws_config_config_rule.securityhub_kinesis_stream_encrypted_1456a235
  id = "securityhub-kinesis-stream-encrypted-1456a235"
}

import {
  to = aws_config_config_rule.securityhub_kms_cmk_not_scheduled_for_deletion_2_109ab27f
  id = "securityhub-kms-cmk-not-scheduled-for-deletion-2-109ab27f"
}

import {
  to = aws_config_config_rule.securityhub_kms_key_policy_no_public_access_e40c3e07
  id = "securityhub-kms-key-policy-no-public-access-e40c3e07"
}

import {
  to = aws_config_config_rule.securityhub_lambda_function_public_access_prohibited_a883f044
  id = "securityhub-lambda-function-public-access-prohibited-a883f044"
}

import {
  to = aws_config_config_rule.securityhub_lambda_function_settings_check_fb818cef
  id = "securityhub-lambda-function-settings-check-fb818cef"
}

import {
  to = aws_config_config_rule.securityhub_lambda_vpc_multi_az_check_0afbb09f
  id = "securityhub-lambda-vpc-multi-az-check-0afbb09f"
}

import {
  to = aws_config_config_rule.securityhub_macie_auto_sensitive_data_discovery_check_309db21f
  id = "securityhub-macie-auto-sensitive-data-discovery-check-309db21f"
}

import {
  to = aws_config_config_rule.securityhub_macie_status_check_670503fd
  id = "securityhub-macie-status-check-670503fd"
}

import {
  to = aws_config_config_rule.securityhub_mariadb_publish_logs_to_cloudwatch_logs_0ea8ca6c
  id = "securityhub-mariadb-publish-logs-to-cloudwatch-logs-0ea8ca6c"
}

import {
  to = aws_config_config_rule.securityhub_mfa_enabled_for_iam_console_access_e7bc0047
  id = "securityhub-mfa-enabled-for-iam-console-access-e7bc0047"
}

import {
  to = aws_config_config_rule.securityhub_mq_cloudwatch_audit_log_enabled_7b00f121
  id = "securityhub-mq-cloudwatch-audit-log-enabled-7b00f121"
}

import {
  to = aws_config_config_rule.securityhub_msk_cluster_public_access_disabled_1fe43f30
  id = "securityhub-msk-cluster-public-access-disabled-1fe43f30"
}

import {
  to = aws_config_config_rule.securityhub_msk_in_cluster_node_require_tls_de9477e1
  id = "securityhub-msk-in-cluster-node-require-tls-de9477e1"
}

import {
  to = aws_config_config_rule.securityhub_msk_unrestricted_access_check_eb47217b
  id = "securityhub-msk-unrestricted-access-check-eb47217b"
}

import {
  to = aws_config_config_rule.securityhub_multi_region_cloud_trail_enabled_b8841665
  id = "securityhub-multi-region-cloud-trail-enabled-b8841665"
}

import {
  to = aws_config_config_rule.securityhub_nacl_no_unrestricted_ssh_rdp_950f0dd7
  id = "securityhub-nacl-no-unrestricted-ssh-rdp-950f0dd7"
}

import {
  to = aws_config_config_rule.securityhub_neptune_cluster_backup_retention_check_61a66783
  id = "securityhub-neptune-cluster-backup-retention-check-61a66783"
}

import {
  to = aws_config_config_rule.securityhub_neptune_cluster_cloudwatch_log_export_enabled_e5c8c0fa
  id = "securityhub-neptune-cluster-cloudwatch-log-export-enabled-e5c8c0fa"
}

import {
  to = aws_config_config_rule.securityhub_neptune_cluster_copy_tags_to_snapshot_enabled_1a01887d
  id = "securityhub-neptune-cluster-copy-tags-to-snapshot-enabled-1a01887d"
}

import {
  to = aws_config_config_rule.securityhub_neptune_cluster_deletion_protection_enabled_10b6af63
  id = "securityhub-neptune-cluster-deletion-protection-enabled-10b6af63"
}

import {
  to = aws_config_config_rule.securityhub_neptune_cluster_encrypted_5eeec3aa
  id = "securityhub-neptune-cluster-encrypted-5eeec3aa"
}

import {
  to = aws_config_config_rule.securityhub_neptune_cluster_iam_database_authentication_2641b170
  id = "securityhub-neptune-cluster-iam-database-authentication-2641b170"
}

import {
  to = aws_config_config_rule.securityhub_neptune_cluster_snapshot_encrypted_4386d755
  id = "securityhub-neptune-cluster-snapshot-encrypted-4386d755"
}

import {
  to = aws_config_config_rule.securityhub_neptune_cluster_snapshot_public_prohibited_71bee87d
  id = "securityhub-neptune-cluster-snapshot-public-prohibited-71bee87d"
}

import {
  to = aws_config_config_rule.securityhub_netfw_deletion_protection_enabled_350b0dfe
  id = "securityhub-netfw-deletion-protection-enabled-350b0dfe"
}

import {
  to = aws_config_config_rule.securityhub_netfw_logging_enabled_55988936
  id = "securityhub-netfw-logging-enabled-55988936"
}

import {
  to = aws_config_config_rule.securityhub_netfw_policy_default_action_fragment_packets_bc8428ed
  id = "securityhub-netfw-policy-default-action-fragment-packets-bc8428ed"
}

import {
  to = aws_config_config_rule.securityhub_netfw_policy_default_action_full_packets_f04aacaf
  id = "securityhub-netfw-policy-default-action-full-packets-f04aacaf"
}

import {
  to = aws_config_config_rule.securityhub_netfw_policy_rule_group_associated_c007ba45
  id = "securityhub-netfw-policy-rule-group-associated-c007ba45"
}

import {
  to = aws_config_config_rule.securityhub_netfw_stateless_rule_group_not_empty_bc208b44
  id = "securityhub-netfw-stateless-rule-group-not-empty-bc208b44"
}

import {
  to = aws_config_config_rule.securityhub_netfw_subnet_change_protection_enabled_0355ede8
  id = "securityhub-netfw-subnet-change-protection-enabled-0355ede8"
}

import {
  to = aws_config_config_rule.securityhub_opensearch_access_control_enabled_919667b0
  id = "securityhub-opensearch-access-control-enabled-919667b0"
}

import {
  to = aws_config_config_rule.securityhub_opensearch_audit_logging_enabled_918bbf48
  id = "securityhub-opensearch-audit-logging-enabled-918bbf48"
}

import {
  to = aws_config_config_rule.securityhub_opensearch_data_node_fault_tolerance_2dfe4590
  id = "securityhub-opensearch-data-node-fault-tolerance-2dfe4590"
}

import {
  to = aws_config_config_rule.securityhub_opensearch_encrypted_at_rest_12c0e9e7
  id = "securityhub-opensearch-encrypted-at-rest-12c0e9e7"
}

import {
  to = aws_config_config_rule.securityhub_opensearch_https_required_64989013
  id = "securityhub-opensearch-https-required-64989013"
}

import {
  to = aws_config_config_rule.securityhub_opensearch_in_vpc_only_4c5551eb
  id = "securityhub-opensearch-in-vpc-only-4c5551eb"
}

import {
  to = aws_config_config_rule.securityhub_opensearch_logs_to_cloudwatch_0f845eb0
  id = "securityhub-opensearch-logs-to-cloudwatch-0f845eb0"
}

import {
  to = aws_config_config_rule.securityhub_opensearch_node_to_node_encryption_check_27919d7f
  id = "securityhub-opensearch-node-to-node-encryption-check-27919d7f"
}

import {
  to = aws_config_config_rule.securityhub_opensearch_update_check_43d55976
  id = "securityhub-opensearch-update-check-43d55976"
}

import {
  to = aws_config_config_rule.securityhub_rds_aurora_mysql_audit_logging_enabled_ce6545f7
  id = "securityhub-rds-aurora-mysql-audit-logging-enabled-ce6545f7"
}

import {
  to = aws_config_config_rule.securityhub_rds_aurora_postgresql_logs_to_cloudwatch_41f1c494
  id = "securityhub-rds-aurora-postgresql-logs-to-cloudwatch-41f1c494"
}

import {
  to = aws_config_config_rule.securityhub_rds_automatic_minor_version_upgrade_enabled_e47bb843
  id = "securityhub-rds-automatic-minor-version-upgrade-enabled-e47bb843"
}

import {
  to = aws_config_config_rule.securityhub_rds_cluster_auto_minor_version_upgrade_enable_170eee60
  id = "securityhub-rds-cluster-auto-minor-version-upgrade-enable-170eee60"
}

import {
  to = aws_config_config_rule.securityhub_rds_cluster_backup_retention_check_d32e760e
  id = "securityhub-rds-cluster-backup-retention-check-d32e760e"
}

import {
  to = aws_config_config_rule.securityhub_rds_cluster_copy_tags_to_snapshots_enabled_4ac5b05f
  id = "securityhub-rds-cluster-copy-tags-to-snapshots-enabled-4ac5b05f"
}

import {
  to = aws_config_config_rule.securityhub_rds_cluster_default_admin_check_0943344f
  id = "securityhub-rds-cluster-default-admin-check-0943344f"
}

import {
  to = aws_config_config_rule.securityhub_rds_cluster_deletion_protection_enabled_3f7de8a6
  id = "securityhub-rds-cluster-deletion-protection-enabled-3f7de8a6"
}

import {
  to = aws_config_config_rule.securityhub_rds_cluster_encrypted_at_rest_684044b0
  id = "securityhub-rds-cluster-encrypted-at-rest-684044b0"
}

import {
  to = aws_config_config_rule.securityhub_rds_cluster_event_notifications_configured_6b08afe5
  id = "securityhub-rds-cluster-event-notifications-configured-6b08afe5"
}

import {
  to = aws_config_config_rule.securityhub_rds_cluster_iam_authentication_enabled_ec00cefb
  id = "securityhub-rds-cluster-iam-authentication-enabled-ec00cefb"
}

import {
  to = aws_config_config_rule.securityhub_rds_cluster_multi_az_enabled_eddb641d
  id = "securityhub-rds-cluster-multi-az-enabled-eddb641d"
}

import {
  to = aws_config_config_rule.securityhub_rds_enhanced_monitoring_enabled_713500f4
  id = "securityhub-rds-enhanced-monitoring-enabled-713500f4"
}

import {
  to = aws_config_config_rule.securityhub_rds_instance_copy_tags_to_snapshots_enabled_fd12241c
  id = "securityhub-rds-instance-copy-tags-to-snapshots-enabled-fd12241c"
}

import {
  to = aws_config_config_rule.securityhub_rds_instance_default_admin_check_a430684a
  id = "securityhub-rds-instance-default-admin-check-a430684a"
}

import {
  to = aws_config_config_rule.securityhub_rds_instance_deletion_protection_enabled_89ede897
  id = "securityhub-rds-instance-deletion-protection-enabled-89ede897"
}

import {
  to = aws_config_config_rule.securityhub_rds_instance_event_notifications_configured_567c6cd5
  id = "securityhub-rds-instance-event-notifications-configured-567c6cd5"
}

import {
  to = aws_config_config_rule.securityhub_rds_instance_iam_authentication_enabled_f8560adc
  id = "securityhub-rds-instance-iam-authentication-enabled-f8560adc"
}

import {
  to = aws_config_config_rule.securityhub_rds_instance_public_access_check_d1b8a0df
  id = "securityhub-rds-instance-public-access-check-d1b8a0df"
}

import {
  to = aws_config_config_rule.securityhub_rds_instance_subnet_igw_check_1e4cd654
  id = "securityhub-rds-instance-subnet-igw-check-1e4cd654"
}

import {
  to = aws_config_config_rule.securityhub_rds_logging_enabled_6d577caa
  id = "securityhub-rds-logging-enabled-6d577caa"
}

import {
  to = aws_config_config_rule.securityhub_rds_mariadb_instance_encrypted_in_transit_e0a25b27
  id = "securityhub-rds-mariadb-instance-encrypted-in-transit-e0a25b27"
}

import {
  to = aws_config_config_rule.securityhub_rds_multi_az_support_ce8927e2
  id = "securityhub-rds-multi-az-support-ce8927e2"
}

import {
  to = aws_config_config_rule.securityhub_rds_mysql_cluster_copy_tags_to_snapshot_check_39dcd630
  id = "securityhub-rds-mysql-cluster-copy-tags-to-snapshot-check-39dcd630"
}

import {
  to = aws_config_config_rule.securityhub_rds_mysql_instance_encrypted_in_transit_c6b78a93
  id = "securityhub-rds-mysql-instance-encrypted-in-transit-c6b78a93"
}

import {
  to = aws_config_config_rule.securityhub_rds_no_default_ports_c49b832a
  id = "securityhub-rds-no-default-ports-c49b832a"
}

import {
  to = aws_config_config_rule.securityhub_rds_pg_event_notifications_configured_79fdb794
  id = "securityhub-rds-pg-event-notifications-configured-79fdb794"
}

import {
  to = aws_config_config_rule.securityhub_rds_pgsql_cluster_copy_tags_to_snapshot_check_863d2940
  id = "securityhub-rds-pgsql-cluster-copy-tags-to-snapshot-check-863d2940"
}

import {
  to = aws_config_config_rule.securityhub_rds_postgres_instance_encrypted_in_transit_051d4e9a
  id = "securityhub-rds-postgres-instance-encrypted-in-transit-051d4e9a"
}

import {
  to = aws_config_config_rule.securityhub_rds_postgresql_logs_to_cloudwatch_be826cd3
  id = "securityhub-rds-postgresql-logs-to-cloudwatch-be826cd3"
}

import {
  to = aws_config_config_rule.securityhub_rds_proxy_tls_encryption_f2a2901c
  id = "securityhub-rds-proxy-tls-encryption-f2a2901c"
}

import {
  to = aws_config_config_rule.securityhub_rds_sg_event_notifications_configured_228b753a
  id = "securityhub-rds-sg-event-notifications-configured-228b753a"
}

import {
  to = aws_config_config_rule.securityhub_rds_snapshot_encrypted_12535c8b
  id = "securityhub-rds-snapshot-encrypted-12535c8b"
}

import {
  to = aws_config_config_rule.securityhub_rds_sql_server_logs_to_cloudwatch_2291fdd9
  id = "securityhub-rds-sql-server-logs-to-cloudwatch-2291fdd9"
}

import {
  to = aws_config_config_rule.securityhub_rds_sqlserver_encrypted_in_transit_1cd4bf8e
  id = "securityhub-rds-sqlserver-encrypted-in-transit-1cd4bf8e"
}

import {
  to = aws_config_config_rule.securityhub_rds_storage_encrypted_1097c62a
  id = "securityhub-rds-storage-encrypted-1097c62a"
}

import {
  to = aws_config_config_rule.securityhub_redshift_backup_enabled_80209429
  id = "securityhub-redshift-backup-enabled-80209429"
}

import {
  to = aws_config_config_rule.securityhub_redshift_cluster_audit_logging_enabled_1c85bab1
  id = "securityhub-redshift-cluster-audit-logging-enabled-1c85bab1"
}

import {
  to = aws_config_config_rule.securityhub_redshift_cluster_kms_enabled_7ff8e081
  id = "securityhub-redshift-cluster-kms-enabled-7ff8e081"
}

import {
  to = aws_config_config_rule.securityhub_redshift_cluster_maintenancesettings_check_b1982637
  id = "securityhub-redshift-cluster-maintenancesettings-check-b1982637"
}

import {
  to = aws_config_config_rule.securityhub_redshift_cluster_multi_az_enabled_be087183
  id = "securityhub-redshift-cluster-multi-az-enabled-be087183"
}

import {
  to = aws_config_config_rule.securityhub_redshift_cluster_public_access_check_bfa5f204
  id = "securityhub-redshift-cluster-public-access-check-bfa5f204"
}

import {
  to = aws_config_config_rule.securityhub_redshift_default_admin_check_10b1b2b2
  id = "securityhub-redshift-default-admin-check-10b1b2b2"
}

import {
  to = aws_config_config_rule.securityhub_redshift_enhanced_vpc_routing_enabled_5aa44fc5
  id = "securityhub-redshift-enhanced-vpc-routing-enabled-5aa44fc5"
}

import {
  to = aws_config_config_rule.securityhub_redshift_require_tls_ssl_c862ddd2
  id = "securityhub-redshift-require-tls-ssl-c862ddd2"
}

import {
  to = aws_config_config_rule.securityhub_redshift_unrestricted_port_access_d3a9b7f9
  id = "securityhub-redshift-unrestricted-port-access-d3a9b7f9"
}

import {
  to = aws_config_config_rule.securityhub_restricted_ssh_1399bc40
  id = "securityhub-restricted-ssh-1399bc40"
}

import {
  to = aws_config_config_rule.securityhub_root_account_hardware_mfa_enabled_3d36284a
  id = "securityhub-root-account-hardware-mfa-enabled-3d36284a"
}

import {
  to = aws_config_config_rule.securityhub_root_account_mfa_enabled_12c4ae4d
  id = "securityhub-root-account-mfa-enabled-12c4ae4d"
}

import {
  to = aws_config_config_rule.securityhub_s3_access_point_public_access_blocks_79336751
  id = "securityhub-s3-access-point-public-access-blocks-79336751"
}

import {
  to = aws_config_config_rule.securityhub_s3_account_level_public_access_blocks_periodic_8e54bdf5
  id = "securityhub-s3-account-level-public-access-blocks-periodic-8e54bdf5"
}

import {
  to = aws_config_config_rule.securityhub_s3_bucket_acl_prohibited_85ecbc1a
  id = "securityhub-s3-bucket-acl-prohibited-85ecbc1a"
}

import {
  to = aws_config_config_rule.securityhub_s3_bucket_blacklisted_actions_prohibited_890d7afd
  id = "securityhub-s3-bucket-blacklisted-actions-prohibited-890d7afd"
}

import {
  to = aws_config_config_rule.securityhub_s3_bucket_level_public_access_prohibited_0bd2d42f
  id = "securityhub-s3-bucket-level-public-access-prohibited-0bd2d42f"
}

import {
  to = aws_config_config_rule.securityhub_s3_bucket_logging_enabled_aa58851b
  id = "securityhub-s3-bucket-logging-enabled-aa58851b"
}

import {
  to = aws_config_config_rule.securityhub_s3_bucket_public_read_prohibited_b9d9b3fd
  id = "securityhub-s3-bucket-public-read-prohibited-b9d9b3fd"
}

import {
  to = aws_config_config_rule.securityhub_s3_bucket_public_write_prohibited_04cc2087
  id = "securityhub-s3-bucket-public-write-prohibited-04cc2087"
}

import {
  to = aws_config_config_rule.securityhub_s3_bucket_ssl_requests_only_bfac44f3
  id = "securityhub-s3-bucket-ssl-requests-only-bfac44f3"
}

import {
  to = aws_config_config_rule.securityhub_s3_lifecycle_policy_check_670b36e8
  id = "securityhub-s3-lifecycle-policy-check-670b36e8"
}

import {
  to = aws_config_config_rule.securityhub_sagemaker_endpoint_config_prod_instance_count_41a649a5
  id = "securityhub-sagemaker-endpoint-config-prod-instance-count-41a649a5"
}

import {
  to = aws_config_config_rule.securityhub_sagemaker_model_isolation_enabled_1f62b4fa
  id = "securityhub-sagemaker-model-isolation-enabled-1f62b4fa"
}

import {
  to = aws_config_config_rule.securityhub_sagemaker_notebook_instance_inside_vpc_2c79afca
  id = "securityhub-sagemaker-notebook-instance-inside-vpc-2c79afca"
}

import {
  to = aws_config_config_rule.securityhub_sagemaker_notebook_instance_platform_version_365646ec
  id = "securityhub-sagemaker-notebook-instance-platform-version-365646ec"
}

import {
  to = aws_config_config_rule.securityhub_sagemaker_notebook_instance_root_access_check_698e6e9a
  id = "securityhub-sagemaker-notebook-instance-root-access-check-698e6e9a"
}

import {
  to = aws_config_config_rule.securityhub_sagemaker_notebook_no_direct_internet_access_676195e7
  id = "securityhub-sagemaker-notebook-no-direct-internet-access-676195e7"
}

import {
  to = aws_config_config_rule.securityhub_secretsmanager_rotation_enabled_check_5ecd3d81
  id = "securityhub-secretsmanager-rotation-enabled-check-5ecd3d81"
}

import {
  to = aws_config_config_rule.securityhub_secretsmanager_scheduled_rotation_success_check_ce9dc473
  id = "securityhub-secretsmanager-scheduled-rotation-success-check-ce9dc473"
}

import {
  to = aws_config_config_rule.securityhub_secretsmanager_secret_periodic_rotation_d7ff7990
  id = "securityhub-secretsmanager-secret-periodic-rotation-d7ff7990"
}

import {
  to = aws_config_config_rule.securityhub_secretsmanager_secret_unused_f5b67c7d
  id = "securityhub-secretsmanager-secret-unused-f5b67c7d"
}

import {
  to = aws_config_config_rule.securityhub_security_account_information_provided_85566181
  id = "securityhub-security-account-information-provided-85566181"
}

import {
  to = aws_config_config_rule.securityhub_service_catalog_shared_within_organization_44952c7a
  id = "securityhub-service-catalog-shared-within-organization-44952c7a"
}

import {
  to = aws_config_config_rule.securityhub_service_vpc_endpoint_enabled_565a43bd
  id = "securityhub-service-vpc-endpoint-enabled-565a43bd"
}

import {
  to = aws_config_config_rule.securityhub_ses_sending_tls_required_9aa3faad
  id = "securityhub-ses-sending-tls-required-9aa3faad"
}

import {
  to = aws_config_config_rule.securityhub_sns_topic_no_public_access_de1c4b92
  id = "securityhub-sns-topic-no-public-access-de1c4b92"
}

import {
  to = aws_config_config_rule.securityhub_sqs_queue_encrypted_76d45072
  id = "securityhub-sqs-queue-encrypted-76d45072"
}

import {
  to = aws_config_config_rule.securityhub_sqs_queue_no_public_access_ce93fbc8
  id = "securityhub-sqs-queue-no-public-access-ce93fbc8"
}

import {
  to = aws_config_config_rule.securityhub_ssm_automation_block_public_sharing_aecfaef7
  id = "securityhub-ssm-automation-block-public-sharing-aecfaef7"
}

import {
  to = aws_config_config_rule.securityhub_ssm_automation_logging_enabled_da75da6d
  id = "securityhub-ssm-automation-logging-enabled-da75da6d"
}

import {
  to = aws_config_config_rule.securityhub_ssm_document_not_public_8407075b
  id = "securityhub-ssm-document-not-public-8407075b"
}

import {
  to = aws_config_config_rule.securityhub_step_functions_state_machine_logging_enabled_84c62904
  id = "securityhub-step-functions-state-machine-logging-enabled-84c62904"
}

import {
  to = aws_config_config_rule.securityhub_subnet_auto_assign_public_ip_disabled_78d845ef
  id = "securityhub-subnet-auto-assign-public-ip-disabled-78d845ef"
}

import {
  to = aws_config_config_rule.securityhub_transfer_connector_logging_enabled_b885584a
  id = "securityhub-transfer-connector-logging-enabled-b885584a"
}

import {
  to = aws_config_config_rule.securityhub_transfer_family_server_no_ftp_9865c571
  id = "securityhub-transfer-family-server-no-ftp-9865c571"
}

import {
  to = aws_config_config_rule.securityhub_vpc_default_security_group_closed_bb2a1997
  id = "securityhub-vpc-default-security-group-closed-bb2a1997"
}

import {
  to = aws_config_config_rule.securityhub_vpc_endpoint_enabled_ecr_api_ff006b1d
  id = "securityhub-vpc-endpoint-enabled-ecr-api-ff006b1d"
}

import {
  to = aws_config_config_rule.securityhub_vpc_endpoint_enabled_ecr_dkr_a177d72d
  id = "securityhub-vpc-endpoint-enabled-ecr-dkr-a177d72d"
}

import {
  to = aws_config_config_rule.securityhub_vpc_endpoint_enabled_ssm_beccfda3
  id = "securityhub-vpc-endpoint-enabled-ssm-beccfda3"
}

import {
  to = aws_config_config_rule.securityhub_vpc_flow_logs_enabled_373a589d
  id = "securityhub-vpc-flow-logs-enabled-373a589d"
}

import {
  to = aws_config_config_rule.securityhub_vpc_network_acl_unused_check_ddd5edff
  id = "securityhub-vpc-network-acl-unused-check-ddd5edff"
}

import {
  to = aws_config_config_rule.securityhub_vpc_sg_open_only_to_authorized_ports_e7bf8bce
  id = "securityhub-vpc-sg-open-only-to-authorized-ports-e7bf8bce"
}

import {
  to = aws_config_config_rule.securityhub_vpc_sg_restricted_common_ports_29874e97
  id = "securityhub-vpc-sg-restricted-common-ports-29874e97"
}

import {
  to = aws_config_config_rule.securityhub_vpc_vpn_2_tunnels_up_fd4b9305
  id = "securityhub-vpc-vpn-2-tunnels-up-fd4b9305"
}

import {
  to = aws_config_config_rule.securityhub_waf_regional_rule_not_empty_79dbee49
  id = "securityhub-waf-regional-rule-not-empty-79dbee49"
}

import {
  to = aws_config_config_rule.securityhub_waf_regional_rulegroup_not_empty_eb61507a
  id = "securityhub-waf-regional-rulegroup-not-empty-eb61507a"
}

import {
  to = aws_config_config_rule.securityhub_waf_regional_webacl_not_empty_c4fbd1da
  id = "securityhub-waf-regional-webacl-not-empty-c4fbd1da"
}

import {
  to = aws_config_config_rule.securityhub_wafv2_rulegroup_logging_enabled_40286ee3
  id = "securityhub-wafv2-rulegroup-logging-enabled-40286ee3"
}

import {
  to = aws_config_config_rule.securityhub_wafv2_webacl_not_empty_fdff1f82
  id = "securityhub-wafv2-webacl-not-empty-fdff1f82"
}

import {
  to = aws_config_config_rule.securityhub_workspaces_root_volume_encryption_enabled_7758c373
  id = "securityhub-workspaces-root-volume-encryption-enabled-7758c373"
}

import {
  to = aws_config_config_rule.securityhub_workspaces_user_volume_encryption_enabled_993a4e0d
  id = "securityhub-workspaces-user-volume-encryption-enabled-993a4e0d"
}

