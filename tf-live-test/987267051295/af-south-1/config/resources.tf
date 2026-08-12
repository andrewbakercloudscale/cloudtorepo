# Auto-generated resource skeletons.
# After running 'terraform plan -generate-config-out=generated.tf',
# replace these stubs with the contents of generated.tf.

resource "aws_config_configuration_recorder" "default" {}

resource "aws_config_configuration_recorder_status" "default" {}

resource "aws_config_delivery_channel" "default" {}

resource "aws_config_config_rule" "account_part_of_organizations" {}

resource "aws_config_config_rule" "cloudtrail_enabled" {}

resource "aws_config_config_rule" "cloudtrail_security_trail_enabled" {}

resource "aws_config_config_rule" "ec2_security_group_attached_to_eni" {}

resource "aws_config_config_rule" "securityhub_access_keys_rotated_774aa6c9" {}

resource "aws_config_config_rule" "securityhub_acm_certificate_expiration_check_e2df179f" {}

resource "aws_config_config_rule" "securityhub_acm_certificate_rsa_check_383f707d" {}

resource "aws_config_config_rule" "securityhub_acm_pca_root_ca_disabled_33b9d80b" {}

resource "aws_config_config_rule" "securityhub_alb_desync_mode_check_0e7d0df3" {}

resource "aws_config_config_rule" "securityhub_alb_http_drop_invalid_header_enabled_69a3900a" {}

resource "aws_config_config_rule" "securityhub_alb_http_to_https_redirection_check_9eb976ce" {}

resource "aws_config_config_rule" "securityhub_api_gw_associated_with_waf_035510a9" {}

resource "aws_config_config_rule" "securityhub_api_gw_cache_encrypted_fc0a58cd" {}

resource "aws_config_config_rule" "securityhub_api_gw_execution_logging_enabled_09bb5f73" {}

resource "aws_config_config_rule" "securityhub_api_gw_ssl_enabled_1ab44c4c" {}

resource "aws_config_config_rule" "securityhub_api_gw_xray_enabled_dc31fd7a" {}

resource "aws_config_config_rule" "securityhub_api_gwv2_access_logs_enabled_fcfebbe4" {}

resource "aws_config_config_rule" "securityhub_api_gwv2_authorization_type_configured_93253d61" {}

resource "aws_config_config_rule" "securityhub_apigatewayv2_integration_private_https_enabled_f7203c64" {}

resource "aws_config_config_rule" "securityhub_appsync_authorization_check_94118ac3" {}

resource "aws_config_config_rule" "securityhub_appsync_logging_enabled_e4ff932a" {}

resource "aws_config_config_rule" "securityhub_athena_workgroup_logging_enabled_e7740166" {}

resource "aws_config_config_rule" "securityhub_aurora_mysql_cluster_audit_logging_bbda887d" {}

resource "aws_config_config_rule" "securityhub_autoscaling_group_elb_healthcheck_required_17d48b72" {}

resource "aws_config_config_rule" "securityhub_autoscaling_launch_config_public_ip_disabled_425834c7" {}

resource "aws_config_config_rule" "securityhub_autoscaling_launch_template_2f1ad2a5" {}

resource "aws_config_config_rule" "securityhub_autoscaling_launchconfig_requires_imdsv2_ec43f147" {}

resource "aws_config_config_rule" "securityhub_autoscaling_multiple_az_ec0ef640" {}

resource "aws_config_config_rule" "securityhub_autoscaling_multiple_instance_types_5d6c4874" {}

resource "aws_config_config_rule" "securityhub_backup_recovery_point_encrypted_1514952e" {}

resource "aws_config_config_rule" "securityhub_beanstalk_enhanced_health_reporting_enabled_d33ac9a4" {}

resource "aws_config_config_rule" "securityhub_clb_desync_mode_check_585c14b4" {}

resource "aws_config_config_rule" "securityhub_clb_multiple_az_8cc5fc29" {}

resource "aws_config_config_rule" "securityhub_cloud_trail_cloud_watch_logs_enabled_3733030e" {}

resource "aws_config_config_rule" "securityhub_cloud_trail_encryption_enabled_04a14217" {}

resource "aws_config_config_rule" "securityhub_cloud_trail_log_file_validation_enabled_0af538a9" {}

resource "aws_config_config_rule" "securityhub_cloudformation_stack_service_role_check_f184aceb" {}

resource "aws_config_config_rule" "securityhub_cloudformation_termination_protection_check_b874d3da" {}

resource "aws_config_config_rule" "securityhub_cmk_backing_key_rotation_enabled_912506e4" {}

resource "aws_config_config_rule" "securityhub_codebuild_project_envvar_awscred_check_fd4cc9fd" {}

resource "aws_config_config_rule" "securityhub_codebuild_project_logging_enabled_7c524c5f" {}

resource "aws_config_config_rule" "securityhub_codebuild_project_s3_logs_encrypted_65037823" {}

resource "aws_config_config_rule" "securityhub_codebuild_project_source_repo_url_check_634f4fe3" {}

resource "aws_config_config_rule" "securityhub_codebuild_report_group_encrypted_at_rest_80e7d4db" {}

resource "aws_config_config_rule" "securityhub_cognito_identity_pool_unauth_access_check_105a7237" {}

resource "aws_config_config_rule" "securityhub_cognito_user_pool_deletion_protection_enabled_79902d09" {}

resource "aws_config_config_rule" "securityhub_cognito_user_pool_mfa_enabled_96631858" {}

resource "aws_config_config_rule" "securityhub_cognito_user_pool_password_policy_check_f11f7585" {}

resource "aws_config_config_rule" "securityhub_cognito_userpool_cust_auth_threat_full_check_3c4da202" {}

resource "aws_config_config_rule" "securityhub_connect_instance_logging_enabled_517cc58a" {}

resource "aws_config_config_rule" "securityhub_custom_eventbus_policy_attached_6cb2ea7e" {}

resource "aws_config_config_rule" "securityhub_datasync_task_logging_enabled_8767c79d" {}

resource "aws_config_config_rule" "securityhub_db_instance_backup_enabled_f7193f10" {}

resource "aws_config_config_rule" "securityhub_dms_auto_minor_version_upgrade_check_7d8a50d2" {}

resource "aws_config_config_rule" "securityhub_dms_endpoint_ssl_configured_dc0108bd" {}

resource "aws_config_config_rule" "securityhub_dms_mongo_db_authentication_enabled_99ef788b" {}

resource "aws_config_config_rule" "securityhub_dms_redis_tls_enabled_e989b34b" {}

resource "aws_config_config_rule" "securityhub_dms_replication_instance_multi_az_enabled_e0a9dcc5" {}

resource "aws_config_config_rule" "securityhub_dms_replication_not_public_870758d3" {}

resource "aws_config_config_rule" "securityhub_dms_replication_task_sourcedb_logging_7e5f58a0" {}

resource "aws_config_config_rule" "securityhub_dms_replication_task_targetdb_logging_8ae3ed21" {}

resource "aws_config_config_rule" "securityhub_dynamodb_autoscaling_enabled_840efbe1" {}

resource "aws_config_config_rule" "securityhub_dynamodb_pitr_enabled_6d48a58d" {}

resource "aws_config_config_rule" "securityhub_dynamodb_table_deletion_protection_enabled_cc10289e" {}

resource "aws_config_config_rule" "securityhub_ebs_snapshot_block_public_access_b68b6dd7" {}

resource "aws_config_config_rule" "securityhub_ebs_snapshot_public_restorable_check_54d7c5d8" {}

resource "aws_config_config_rule" "securityhub_ec2_client_vpn_connection_log_enabled_c24c040b" {}

resource "aws_config_config_rule" "securityhub_ec2_ebs_encryption_by_default_4d352b12" {}

resource "aws_config_config_rule" "securityhub_ec2_enis_source_destination_check_enabled_0deac96e" {}

resource "aws_config_config_rule" "securityhub_ec2_imdsv2_check_a97e889b" {}

resource "aws_config_config_rule" "securityhub_ec2_instance_managed_by_ssm_04cbcf73" {}

resource "aws_config_config_rule" "securityhub_ec2_instance_multiple_eni_check_2b7082d8" {}

resource "aws_config_config_rule" "securityhub_ec2_instance_no_public_ip_269d5cd0" {}

resource "aws_config_config_rule" "securityhub_ec2_launch_template_imdsv2_check_6b723f4e" {}

resource "aws_config_config_rule" "securityhub_ec2_launch_template_public_ip_disabled_97078948" {}

resource "aws_config_config_rule" "securityhub_ec2_launch_templates_ebs_volume_encrypted_a9dda2cf" {}

resource "aws_config_config_rule" "securityhub_ec2_managedinstance_association_compliance_status_check_0592df4b" {}

resource "aws_config_config_rule" "securityhub_ec2_managedinstance_patch_compliance_310ff521" {}

resource "aws_config_config_rule" "securityhub_ec2_transit_gateway_auto_vpc_attach_disabled_85ad5149" {}

resource "aws_config_config_rule" "securityhub_ec2_vpc_bpa_internet_gateway_blocked_4b22b308" {}

resource "aws_config_config_rule" "securityhub_ec2_vpn_connection_logging_enabled_10c4136e" {}

resource "aws_config_config_rule" "securityhub_ecr_private_image_scanning_enabled_80ed8cc4" {}

resource "aws_config_config_rule" "securityhub_ecr_private_lifecycle_policy_configured_a96e8461" {}

resource "aws_config_config_rule" "securityhub_ecr_private_tag_immutability_enabled_8fd5671d" {}

resource "aws_config_config_rule" "securityhub_ecs_capacity_provider_termination_check_fa461790" {}

resource "aws_config_config_rule" "securityhub_ecs_container_insights_enabled_cc670288" {}

resource "aws_config_config_rule" "securityhub_ecs_containers_nonprivileged_092dd336" {}

resource "aws_config_config_rule" "securityhub_ecs_containers_readonly_access_57a8ddf5" {}

resource "aws_config_config_rule" "securityhub_ecs_fargate_latest_platform_version_307dfd33" {}

resource "aws_config_config_rule" "securityhub_ecs_no_environment_secrets_62e07dba" {}

resource "aws_config_config_rule" "securityhub_ecs_service_assign_public_ip_disabled_5765fd14" {}

resource "aws_config_config_rule" "securityhub_ecs_task_definition_efs_encryption_enabled_1152f368" {}

resource "aws_config_config_rule" "securityhub_ecs_task_definition_linux_user_non_root_2dc8b28b" {}

resource "aws_config_config_rule" "securityhub_ecs_task_definition_log_configuration_5346ead2" {}

resource "aws_config_config_rule" "securityhub_ecs_task_definition_pid_mode_check_8e88353a" {}

resource "aws_config_config_rule" "securityhub_ecs_task_definition_windows_user_non_admin_5624b77a" {}

resource "aws_config_config_rule" "securityhub_ecs_taskset_assign_public_ip_disabled_c2254dfd" {}

resource "aws_config_config_rule" "securityhub_efs_access_point_enforce_root_directory_abe0a9c4" {}

resource "aws_config_config_rule" "securityhub_efs_access_point_enforce_user_identity_5bec47f9" {}

resource "aws_config_config_rule" "securityhub_efs_automatic_backups_enabled_b9d3e723" {}

resource "aws_config_config_rule" "securityhub_efs_encrypted_check_c4673af5" {}

resource "aws_config_config_rule" "securityhub_efs_filesystem_ct_encrypted_baca3ac1" {}

resource "aws_config_config_rule" "securityhub_efs_in_backup_plan_272a281a" {}

resource "aws_config_config_rule" "securityhub_efs_mount_target_public_accessible_c974e5ec" {}

resource "aws_config_config_rule" "securityhub_eks_cluster_log_enabled_922f94cc" {}

resource "aws_config_config_rule" "securityhub_eks_cluster_secrets_encrypted_fac5c9f1" {}

resource "aws_config_config_rule" "securityhub_eks_cluster_supported_version_f1abc0a7" {}

resource "aws_config_config_rule" "securityhub_eks_endpoint_no_public_access_7f93f7b4" {}

resource "aws_config_config_rule" "securityhub_elastic_beanstalk_logs_to_cloudwatch_9225ec61" {}

resource "aws_config_config_rule" "securityhub_elastic_beanstalk_managed_updates_enabled_18001d6a" {}

resource "aws_config_config_rule" "securityhub_elasticache_auto_minor_version_upgrade_check_e1a70454" {}

resource "aws_config_config_rule" "securityhub_elasticache_redis_cluster_automatic_backup_check_0a9765f2" {}

resource "aws_config_config_rule" "securityhub_elasticache_repl_grp_auto_failover_enabled_83fddbaa" {}

resource "aws_config_config_rule" "securityhub_elasticache_repl_grp_encrypted_at_rest_ee6e37d2" {}

resource "aws_config_config_rule" "securityhub_elasticache_repl_grp_encrypted_in_transit_4e395de6" {}

resource "aws_config_config_rule" "securityhub_elasticache_repl_grp_redis_auth_enabled_83545a24" {}

resource "aws_config_config_rule" "securityhub_elasticache_subnet_group_check_b60dd71d" {}

resource "aws_config_config_rule" "securityhub_elasticsearch_audit_logging_enabled_272fb20c" {}

resource "aws_config_config_rule" "securityhub_elasticsearch_data_node_fault_tolerance_c828ee99" {}

resource "aws_config_config_rule" "securityhub_elasticsearch_encrypted_at_rest_2958fcab" {}

resource "aws_config_config_rule" "securityhub_elasticsearch_https_required_c3f868d7" {}

resource "aws_config_config_rule" "securityhub_elasticsearch_in_vpc_only_906f985d" {}

resource "aws_config_config_rule" "securityhub_elasticsearch_logs_to_cloudwatch_431feb80" {}

resource "aws_config_config_rule" "securityhub_elasticsearch_primary_node_fault_tolerance_bd83fcba" {}

resource "aws_config_config_rule" "securityhub_elb_connection_draining_enabled_40ba7f17" {}

resource "aws_config_config_rule" "securityhub_elb_cross_zone_load_balancing_enabled_ff0d16c8" {}

resource "aws_config_config_rule" "securityhub_elb_deletion_protection_enabled_0938a456" {}

resource "aws_config_config_rule" "securityhub_elb_logging_enabled_44f229db" {}

resource "aws_config_config_rule" "securityhub_elb_predefined_security_policy_ssl_check_14fdea58" {}

resource "aws_config_config_rule" "securityhub_elb_tls_https_listeners_only_332d83a3" {}

resource "aws_config_config_rule" "securityhub_elbv2_listener_encryption_in_transit_a77b2558" {}

resource "aws_config_config_rule" "securityhub_elbv2_multiple_az_f39514a8" {}

resource "aws_config_config_rule" "securityhub_elbv2_predefined_security_policy_ssl_check_a956e4d6" {}

resource "aws_config_config_rule" "securityhub_elbv2_targetgroup_healthcheck_protocol_encrypted_8ce87dfa" {}

resource "aws_config_config_rule" "securityhub_elbv2_targetgroup_protocol_encrypted_83a449b1" {}

resource "aws_config_config_rule" "securityhub_emr_block_public_access_6c94cbdf" {}

resource "aws_config_config_rule" "securityhub_emr_master_no_public_ip_c8beb838" {}

resource "aws_config_config_rule" "securityhub_emr_security_configuration_encryption_rest_48be0c5c" {}

resource "aws_config_config_rule" "securityhub_emr_security_configuration_encryption_transit_707c284a" {}

resource "aws_config_config_rule" "securityhub_encrypted_volumes_5c47ec73" {}

resource "aws_config_config_rule" "securityhub_fsx_lustre_copy_tags_to_backups_39fdb1aa" {}

resource "aws_config_config_rule" "securityhub_fsx_ontap_deployment_type_check_878e2154" {}

resource "aws_config_config_rule" "securityhub_fsx_openzfs_copy_tags_enabled_af625a33" {}

resource "aws_config_config_rule" "securityhub_fsx_openzfs_deployment_type_check_e40b5ece" {}

resource "aws_config_config_rule" "securityhub_fsx_windows_deployment_type_check_739cf461" {}

resource "aws_config_config_rule" "securityhub_glue_ml_transform_encrypted_at_rest_14a223c8" {}

resource "aws_config_config_rule" "securityhub_glue_spark_job_supported_version_235567bb" {}

resource "aws_config_config_rule" "securityhub_guardduty_ec2_protection_runtime_enabled_5732378e" {}

resource "aws_config_config_rule" "securityhub_guardduty_ecs_protection_runtime_enabled_98b8af2b" {}

resource "aws_config_config_rule" "securityhub_guardduty_eks_protection_audit_enabled_d9093f63" {}

resource "aws_config_config_rule" "securityhub_guardduty_eks_protection_runtime_enabled_3192c36e" {}

resource "aws_config_config_rule" "securityhub_guardduty_enabled_centralized_17f8f4c8" {}

resource "aws_config_config_rule" "securityhub_guardduty_lambda_protection_enabled_e824e79a" {}

resource "aws_config_config_rule" "securityhub_guardduty_malware_protection_enabled_38d3d9bc" {}

resource "aws_config_config_rule" "securityhub_guardduty_rds_protection_enabled_868c59ef" {}

resource "aws_config_config_rule" "securityhub_guardduty_runtime_monitoring_enabled_0cf2c4d8" {}

resource "aws_config_config_rule" "securityhub_guardduty_s3_protection_enabled_9a4c526b" {}

resource "aws_config_config_rule" "securityhub_iam_customer_policy_blocked_kms_actions_f58ec0a6" {}

resource "aws_config_config_rule" "securityhub_iam_inline_policy_blocked_kms_actions_f469c416" {}

resource "aws_config_config_rule" "securityhub_iam_password_policy_ensure_expires_df4a1475" {}

resource "aws_config_config_rule" "securityhub_iam_password_policy_lowercase_letter_check_acdd215a" {}

resource "aws_config_config_rule" "securityhub_iam_password_policy_minimum_length_check_944f846a" {}

resource "aws_config_config_rule" "securityhub_iam_password_policy_number_check_d62fb361" {}

resource "aws_config_config_rule" "securityhub_iam_password_policy_prevent_reuse_check_40ed51c5" {}

resource "aws_config_config_rule" "securityhub_iam_password_policy_recommended_defaults_05398b0d" {}

resource "aws_config_config_rule" "securityhub_iam_password_policy_symbol_check_74152c48" {}

resource "aws_config_config_rule" "securityhub_iam_password_policy_uppercase_letter_check_3d2e0c96" {}

resource "aws_config_config_rule" "securityhub_iam_policy_no_statements_with_admin_access_a737484e" {}

resource "aws_config_config_rule" "securityhub_iam_policy_no_statements_with_full_access_fd021915" {}

resource "aws_config_config_rule" "securityhub_iam_root_access_key_check_eb277cf8" {}

resource "aws_config_config_rule" "securityhub_iam_user_no_policies_check_68267943" {}

resource "aws_config_config_rule" "securityhub_iam_user_unused_credentials_check_f6ed027d" {}

resource "aws_config_config_rule" "securityhub_inspector_ec2_scan_enabled_45593f67" {}

resource "aws_config_config_rule" "securityhub_inspector_ecr_scan_enabled_27824881" {}

resource "aws_config_config_rule" "securityhub_inspector_lambda_standard_scan_enabled_8addb810" {}

resource "aws_config_config_rule" "securityhub_kinesis_firehose_delivery_stream_encrypted_6c06a2ce" {}

resource "aws_config_config_rule" "securityhub_kinesis_stream_backup_retention_check_c97f9f2e" {}

resource "aws_config_config_rule" "securityhub_kinesis_stream_encrypted_1456a235" {}

resource "aws_config_config_rule" "securityhub_kms_cmk_not_scheduled_for_deletion_2_109ab27f" {}

resource "aws_config_config_rule" "securityhub_kms_key_policy_no_public_access_e40c3e07" {}

resource "aws_config_config_rule" "securityhub_lambda_function_public_access_prohibited_a883f044" {}

resource "aws_config_config_rule" "securityhub_lambda_function_settings_check_fb818cef" {}

resource "aws_config_config_rule" "securityhub_lambda_vpc_multi_az_check_0afbb09f" {}

resource "aws_config_config_rule" "securityhub_macie_auto_sensitive_data_discovery_check_309db21f" {}

resource "aws_config_config_rule" "securityhub_macie_status_check_670503fd" {}

resource "aws_config_config_rule" "securityhub_mariadb_publish_logs_to_cloudwatch_logs_0ea8ca6c" {}

resource "aws_config_config_rule" "securityhub_mfa_enabled_for_iam_console_access_e7bc0047" {}

resource "aws_config_config_rule" "securityhub_mq_cloudwatch_audit_log_enabled_7b00f121" {}

resource "aws_config_config_rule" "securityhub_msk_cluster_public_access_disabled_1fe43f30" {}

resource "aws_config_config_rule" "securityhub_msk_in_cluster_node_require_tls_de9477e1" {}

resource "aws_config_config_rule" "securityhub_msk_unrestricted_access_check_eb47217b" {}

resource "aws_config_config_rule" "securityhub_multi_region_cloud_trail_enabled_b8841665" {}

resource "aws_config_config_rule" "securityhub_nacl_no_unrestricted_ssh_rdp_950f0dd7" {}

resource "aws_config_config_rule" "securityhub_neptune_cluster_backup_retention_check_61a66783" {}

resource "aws_config_config_rule" "securityhub_neptune_cluster_cloudwatch_log_export_enabled_e5c8c0fa" {}

resource "aws_config_config_rule" "securityhub_neptune_cluster_copy_tags_to_snapshot_enabled_1a01887d" {}

resource "aws_config_config_rule" "securityhub_neptune_cluster_deletion_protection_enabled_10b6af63" {}

resource "aws_config_config_rule" "securityhub_neptune_cluster_encrypted_5eeec3aa" {}

resource "aws_config_config_rule" "securityhub_neptune_cluster_iam_database_authentication_2641b170" {}

resource "aws_config_config_rule" "securityhub_neptune_cluster_snapshot_encrypted_4386d755" {}

resource "aws_config_config_rule" "securityhub_neptune_cluster_snapshot_public_prohibited_71bee87d" {}

resource "aws_config_config_rule" "securityhub_netfw_deletion_protection_enabled_350b0dfe" {}

resource "aws_config_config_rule" "securityhub_netfw_logging_enabled_55988936" {}

resource "aws_config_config_rule" "securityhub_netfw_policy_default_action_fragment_packets_bc8428ed" {}

resource "aws_config_config_rule" "securityhub_netfw_policy_default_action_full_packets_f04aacaf" {}

resource "aws_config_config_rule" "securityhub_netfw_policy_rule_group_associated_c007ba45" {}

resource "aws_config_config_rule" "securityhub_netfw_stateless_rule_group_not_empty_bc208b44" {}

resource "aws_config_config_rule" "securityhub_netfw_subnet_change_protection_enabled_0355ede8" {}

resource "aws_config_config_rule" "securityhub_opensearch_access_control_enabled_919667b0" {}

resource "aws_config_config_rule" "securityhub_opensearch_audit_logging_enabled_918bbf48" {}

resource "aws_config_config_rule" "securityhub_opensearch_data_node_fault_tolerance_2dfe4590" {}

resource "aws_config_config_rule" "securityhub_opensearch_encrypted_at_rest_12c0e9e7" {}

resource "aws_config_config_rule" "securityhub_opensearch_https_required_64989013" {}

resource "aws_config_config_rule" "securityhub_opensearch_in_vpc_only_4c5551eb" {}

resource "aws_config_config_rule" "securityhub_opensearch_logs_to_cloudwatch_0f845eb0" {}

resource "aws_config_config_rule" "securityhub_opensearch_node_to_node_encryption_check_27919d7f" {}

resource "aws_config_config_rule" "securityhub_opensearch_update_check_43d55976" {}

resource "aws_config_config_rule" "securityhub_rds_aurora_mysql_audit_logging_enabled_ce6545f7" {}

resource "aws_config_config_rule" "securityhub_rds_aurora_postgresql_logs_to_cloudwatch_41f1c494" {}

resource "aws_config_config_rule" "securityhub_rds_automatic_minor_version_upgrade_enabled_e47bb843" {}

resource "aws_config_config_rule" "securityhub_rds_cluster_auto_minor_version_upgrade_enable_170eee60" {}

resource "aws_config_config_rule" "securityhub_rds_cluster_backup_retention_check_d32e760e" {}

resource "aws_config_config_rule" "securityhub_rds_cluster_copy_tags_to_snapshots_enabled_4ac5b05f" {}

resource "aws_config_config_rule" "securityhub_rds_cluster_default_admin_check_0943344f" {}

resource "aws_config_config_rule" "securityhub_rds_cluster_deletion_protection_enabled_3f7de8a6" {}

resource "aws_config_config_rule" "securityhub_rds_cluster_encrypted_at_rest_684044b0" {}

resource "aws_config_config_rule" "securityhub_rds_cluster_event_notifications_configured_6b08afe5" {}

resource "aws_config_config_rule" "securityhub_rds_cluster_iam_authentication_enabled_ec00cefb" {}

resource "aws_config_config_rule" "securityhub_rds_cluster_multi_az_enabled_eddb641d" {}

resource "aws_config_config_rule" "securityhub_rds_enhanced_monitoring_enabled_713500f4" {}

resource "aws_config_config_rule" "securityhub_rds_instance_copy_tags_to_snapshots_enabled_fd12241c" {}

resource "aws_config_config_rule" "securityhub_rds_instance_default_admin_check_a430684a" {}

resource "aws_config_config_rule" "securityhub_rds_instance_deletion_protection_enabled_89ede897" {}

resource "aws_config_config_rule" "securityhub_rds_instance_event_notifications_configured_567c6cd5" {}

resource "aws_config_config_rule" "securityhub_rds_instance_iam_authentication_enabled_f8560adc" {}

resource "aws_config_config_rule" "securityhub_rds_instance_public_access_check_d1b8a0df" {}

resource "aws_config_config_rule" "securityhub_rds_instance_subnet_igw_check_1e4cd654" {}

resource "aws_config_config_rule" "securityhub_rds_logging_enabled_6d577caa" {}

resource "aws_config_config_rule" "securityhub_rds_mariadb_instance_encrypted_in_transit_e0a25b27" {}

resource "aws_config_config_rule" "securityhub_rds_multi_az_support_ce8927e2" {}

resource "aws_config_config_rule" "securityhub_rds_mysql_cluster_copy_tags_to_snapshot_check_39dcd630" {}

resource "aws_config_config_rule" "securityhub_rds_mysql_instance_encrypted_in_transit_c6b78a93" {}

resource "aws_config_config_rule" "securityhub_rds_no_default_ports_c49b832a" {}

resource "aws_config_config_rule" "securityhub_rds_pg_event_notifications_configured_79fdb794" {}

resource "aws_config_config_rule" "securityhub_rds_pgsql_cluster_copy_tags_to_snapshot_check_863d2940" {}

resource "aws_config_config_rule" "securityhub_rds_postgres_instance_encrypted_in_transit_051d4e9a" {}

resource "aws_config_config_rule" "securityhub_rds_postgresql_logs_to_cloudwatch_be826cd3" {}

resource "aws_config_config_rule" "securityhub_rds_proxy_tls_encryption_f2a2901c" {}

resource "aws_config_config_rule" "securityhub_rds_sg_event_notifications_configured_228b753a" {}

resource "aws_config_config_rule" "securityhub_rds_snapshot_encrypted_12535c8b" {}

resource "aws_config_config_rule" "securityhub_rds_sql_server_logs_to_cloudwatch_2291fdd9" {}

resource "aws_config_config_rule" "securityhub_rds_sqlserver_encrypted_in_transit_1cd4bf8e" {}

resource "aws_config_config_rule" "securityhub_rds_storage_encrypted_1097c62a" {}

resource "aws_config_config_rule" "securityhub_redshift_backup_enabled_80209429" {}

resource "aws_config_config_rule" "securityhub_redshift_cluster_audit_logging_enabled_1c85bab1" {}

resource "aws_config_config_rule" "securityhub_redshift_cluster_kms_enabled_7ff8e081" {}

resource "aws_config_config_rule" "securityhub_redshift_cluster_maintenancesettings_check_b1982637" {}

resource "aws_config_config_rule" "securityhub_redshift_cluster_multi_az_enabled_be087183" {}

resource "aws_config_config_rule" "securityhub_redshift_cluster_public_access_check_bfa5f204" {}

resource "aws_config_config_rule" "securityhub_redshift_default_admin_check_10b1b2b2" {}

resource "aws_config_config_rule" "securityhub_redshift_enhanced_vpc_routing_enabled_5aa44fc5" {}

resource "aws_config_config_rule" "securityhub_redshift_require_tls_ssl_c862ddd2" {}

resource "aws_config_config_rule" "securityhub_redshift_unrestricted_port_access_d3a9b7f9" {}

resource "aws_config_config_rule" "securityhub_restricted_ssh_1399bc40" {}

resource "aws_config_config_rule" "securityhub_root_account_hardware_mfa_enabled_3d36284a" {}

resource "aws_config_config_rule" "securityhub_root_account_mfa_enabled_12c4ae4d" {}

resource "aws_config_config_rule" "securityhub_s3_access_point_public_access_blocks_79336751" {}

resource "aws_config_config_rule" "securityhub_s3_account_level_public_access_blocks_periodic_8e54bdf5" {}

resource "aws_config_config_rule" "securityhub_s3_bucket_acl_prohibited_85ecbc1a" {}

resource "aws_config_config_rule" "securityhub_s3_bucket_blacklisted_actions_prohibited_890d7afd" {}

resource "aws_config_config_rule" "securityhub_s3_bucket_level_public_access_prohibited_0bd2d42f" {}

resource "aws_config_config_rule" "securityhub_s3_bucket_logging_enabled_aa58851b" {}

resource "aws_config_config_rule" "securityhub_s3_bucket_public_read_prohibited_b9d9b3fd" {}

resource "aws_config_config_rule" "securityhub_s3_bucket_public_write_prohibited_04cc2087" {}

resource "aws_config_config_rule" "securityhub_s3_bucket_ssl_requests_only_bfac44f3" {}

resource "aws_config_config_rule" "securityhub_s3_lifecycle_policy_check_670b36e8" {}

resource "aws_config_config_rule" "securityhub_sagemaker_endpoint_config_prod_instance_count_41a649a5" {}

resource "aws_config_config_rule" "securityhub_sagemaker_model_isolation_enabled_1f62b4fa" {}

resource "aws_config_config_rule" "securityhub_sagemaker_notebook_instance_inside_vpc_2c79afca" {}

resource "aws_config_config_rule" "securityhub_sagemaker_notebook_instance_platform_version_365646ec" {}

resource "aws_config_config_rule" "securityhub_sagemaker_notebook_instance_root_access_check_698e6e9a" {}

resource "aws_config_config_rule" "securityhub_sagemaker_notebook_no_direct_internet_access_676195e7" {}

resource "aws_config_config_rule" "securityhub_secretsmanager_rotation_enabled_check_5ecd3d81" {}

resource "aws_config_config_rule" "securityhub_secretsmanager_scheduled_rotation_success_check_ce9dc473" {}

resource "aws_config_config_rule" "securityhub_secretsmanager_secret_periodic_rotation_d7ff7990" {}

resource "aws_config_config_rule" "securityhub_secretsmanager_secret_unused_f5b67c7d" {}

resource "aws_config_config_rule" "securityhub_security_account_information_provided_85566181" {}

resource "aws_config_config_rule" "securityhub_service_catalog_shared_within_organization_44952c7a" {}

resource "aws_config_config_rule" "securityhub_service_vpc_endpoint_enabled_565a43bd" {}

resource "aws_config_config_rule" "securityhub_ses_sending_tls_required_9aa3faad" {}

resource "aws_config_config_rule" "securityhub_sns_topic_no_public_access_de1c4b92" {}

resource "aws_config_config_rule" "securityhub_sqs_queue_encrypted_76d45072" {}

resource "aws_config_config_rule" "securityhub_sqs_queue_no_public_access_ce93fbc8" {}

resource "aws_config_config_rule" "securityhub_ssm_automation_block_public_sharing_aecfaef7" {}

resource "aws_config_config_rule" "securityhub_ssm_automation_logging_enabled_da75da6d" {}

resource "aws_config_config_rule" "securityhub_ssm_document_not_public_8407075b" {}

resource "aws_config_config_rule" "securityhub_step_functions_state_machine_logging_enabled_84c62904" {}

resource "aws_config_config_rule" "securityhub_subnet_auto_assign_public_ip_disabled_78d845ef" {}

resource "aws_config_config_rule" "securityhub_transfer_connector_logging_enabled_b885584a" {}

resource "aws_config_config_rule" "securityhub_transfer_family_server_no_ftp_9865c571" {}

resource "aws_config_config_rule" "securityhub_vpc_default_security_group_closed_bb2a1997" {}

resource "aws_config_config_rule" "securityhub_vpc_endpoint_enabled_ecr_api_ff006b1d" {}

resource "aws_config_config_rule" "securityhub_vpc_endpoint_enabled_ecr_dkr_a177d72d" {}

resource "aws_config_config_rule" "securityhub_vpc_endpoint_enabled_ssm_beccfda3" {}

resource "aws_config_config_rule" "securityhub_vpc_flow_logs_enabled_373a589d" {}

resource "aws_config_config_rule" "securityhub_vpc_network_acl_unused_check_ddd5edff" {}

resource "aws_config_config_rule" "securityhub_vpc_sg_open_only_to_authorized_ports_e7bf8bce" {}

resource "aws_config_config_rule" "securityhub_vpc_sg_restricted_common_ports_29874e97" {}

resource "aws_config_config_rule" "securityhub_vpc_vpn_2_tunnels_up_fd4b9305" {}

resource "aws_config_config_rule" "securityhub_waf_regional_rule_not_empty_79dbee49" {}

resource "aws_config_config_rule" "securityhub_waf_regional_rulegroup_not_empty_eb61507a" {}

resource "aws_config_config_rule" "securityhub_waf_regional_webacl_not_empty_c4fbd1da" {}

resource "aws_config_config_rule" "securityhub_wafv2_rulegroup_logging_enabled_40286ee3" {}

resource "aws_config_config_rule" "securityhub_wafv2_webacl_not_empty_fdff1f82" {}

resource "aws_config_config_rule" "securityhub_workspaces_root_volume_encryption_enabled_7758c373" {}

resource "aws_config_config_rule" "securityhub_workspaces_user_volume_encryption_enabled_993a4e0d" {}

