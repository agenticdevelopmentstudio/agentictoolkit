CREATE TABLE `deploy_integrations` (
	`id` text PRIMARY KEY NOT NULL,
	`platform` text NOT NULL,
	`label` text NOT NULL,
	`config` text DEFAULT '{}' NOT NULL,
	`token_env_var` text,
	`secret_ref` text,
	`is_active` integer DEFAULT true NOT NULL,
	`created_at` integer DEFAULT (unixepoch()) NOT NULL,
	`updated_at` integer DEFAULT (unixepoch()) NOT NULL
);
--> statement-breakpoint
CREATE UNIQUE INDEX `uniq_integration_platform_label` ON `deploy_integrations` (`platform`,`label`);--> statement-breakpoint
CREATE TABLE `deploy_project_meta` (
	`id` text PRIMARY KEY NOT NULL,
	`platform` text NOT NULL,
	`project_name` text NOT NULL,
	`domain` text,
	`git_repo` text,
	`git_branch` text,
	`root_directory` text,
	`framework` text,
	`updated_at` integer DEFAULT (unixepoch()) NOT NULL
);
--> statement-breakpoint
CREATE UNIQUE INDEX `uniq_project_meta` ON `deploy_project_meta` (`platform`,`project_name`);--> statement-breakpoint
CREATE TABLE `deployments` (
	`id` text PRIMARY KEY NOT NULL,
	`platform` text NOT NULL,
	`project_name` text NOT NULL,
	`status` text,
	`build_phase` text,
	`deploy_phase` text DEFAULT 'none' NOT NULL,
	`environment` text,
	`commit_hash` text,
	`commit_message` text,
	`branch` text,
	`commit_repo` text,
	`url` text,
	`live_host` text,
	`created_at` integer NOT NULL,
	`fetched_at` integer DEFAULT (unixepoch()) NOT NULL
);
--> statement-breakpoint
CREATE INDEX `idx_deploy_created` ON `deployments` (`created_at`);--> statement-breakpoint
CREATE TABLE `health_checks` (
	`id` integer PRIMARY KEY AUTOINCREMENT NOT NULL,
	`service_slug` text NOT NULL,
	`status` text NOT NULL,
	`response_time_ms` integer,
	`status_code` integer,
	`error` text,
	`checked_at` integer DEFAULT (unixepoch()) NOT NULL
);
--> statement-breakpoint
CREATE INDEX `idx_health_service_checked` ON `health_checks` (`service_slug`,`checked_at`);--> statement-breakpoint
CREATE TABLE `ignored_deploy_projects` (
	`id` text PRIMARY KEY NOT NULL,
	`platform` text NOT NULL,
	`project_name` text NOT NULL,
	`created_at` integer DEFAULT (unixepoch()) NOT NULL
);
--> statement-breakpoint
CREATE UNIQUE INDEX `uniq_ignored_project` ON `ignored_deploy_projects` (`platform`,`project_name`);--> statement-breakpoint
CREATE TABLE `issues` (
	`id` integer PRIMARY KEY AUTOINCREMENT NOT NULL,
	`target` text NOT NULL,
	`source` text NOT NULL,
	`name` text NOT NULL,
	`environment` text,
	`severity` text NOT NULL,
	`state` text NOT NULL,
	`opened_at` integer DEFAULT (unixepoch()) NOT NULL,
	`resolved_at` integer,
	`status_code` integer,
	`detail` text,
	`source_url` text,
	`live_url` text,
	`commit_hash` text,
	`commit_message` text,
	`commit_repo` text,
	`updated_at` integer DEFAULT (unixepoch()) NOT NULL
);
--> statement-breakpoint
CREATE UNIQUE INDEX `uniq_open_issue_per_target` ON `issues` (`target`) WHERE resolved_at is null;--> statement-breakpoint
CREATE INDEX `idx_issue_resolved` ON `issues` (`resolved_at`);--> statement-breakpoint
CREATE INDEX `idx_issue_source` ON `issues` (`source`);--> statement-breakpoint
CREATE TABLE `metrics_hourly` (
	`id` integer PRIMARY KEY AUTOINCREMENT NOT NULL,
	`service_slug` text NOT NULL,
	`hour` integer NOT NULL,
	`total_checks` integer NOT NULL,
	`healthy_checks` integer NOT NULL,
	`degraded_checks` integer NOT NULL,
	`down_checks` integer NOT NULL,
	`avg_response_time_ms` real,
	`min_response_time_ms` integer,
	`max_response_time_ms` integer
);
--> statement-breakpoint
CREATE UNIQUE INDEX `uniq_metrics_service_hour` ON `metrics_hourly` (`service_slug`,`hour`);--> statement-breakpoint
CREATE TABLE `monitored_endpoints` (
	`id` text PRIMARY KEY NOT NULL,
	`site_id` text NOT NULL,
	`url` text NOT NULL,
	`kind` text DEFAULT 'http' NOT NULL,
	`environment` text,
	`platform` text,
	`deploy_project` text,
	`ignore_project_warning` integer DEFAULT false NOT NULL,
	`expected_status` integer DEFAULT 200 NOT NULL,
	`expect_body` text,
	`check_interval_seconds` integer DEFAULT 60 NOT NULL,
	`is_active` integer DEFAULT true NOT NULL,
	`created_at` integer DEFAULT (unixepoch()) NOT NULL,
	`updated_at` integer DEFAULT (unixepoch()) NOT NULL,
	FOREIGN KEY (`site_id`) REFERENCES `monitored_sites`(`id`) ON UPDATE no action ON DELETE cascade
);
--> statement-breakpoint
CREATE INDEX `idx_endpoint_site` ON `monitored_endpoints` (`site_id`);--> statement-breakpoint
CREATE TABLE `monitored_sites` (
	`id` text PRIMARY KEY NOT NULL,
	`site_group_id` text NOT NULL,
	`slug` text NOT NULL,
	`name` text NOT NULL,
	`created_at` integer DEFAULT (unixepoch()) NOT NULL,
	`updated_at` integer DEFAULT (unixepoch()) NOT NULL,
	FOREIGN KEY (`site_group_id`) REFERENCES `site_groups`(`id`) ON UPDATE no action ON DELETE cascade
);
--> statement-breakpoint
CREATE UNIQUE INDEX `uniq_site_group_site_slug` ON `monitored_sites` (`site_group_id`,`slug`);--> statement-breakpoint
CREATE TABLE `peer_snapshots` (
	`peer_id` text PRIMARY KEY NOT NULL,
	`payload` text,
	`overall` text,
	`reachable` integer DEFAULT false NOT NULL,
	`error` text,
	`fetched_at` integer DEFAULT (unixepoch()) NOT NULL,
	FOREIGN KEY (`peer_id`) REFERENCES `peers`(`id`) ON UPDATE no action ON DELETE cascade
);
--> statement-breakpoint
CREATE TABLE `peers` (
	`id` text PRIMARY KEY NOT NULL,
	`label` text NOT NULL,
	`base_url` text NOT NULL,
	`token` text,
	`is_active` integer DEFAULT true NOT NULL,
	`created_at` integer DEFAULT (unixepoch()) NOT NULL,
	`updated_at` integer DEFAULT (unixepoch()) NOT NULL
);
--> statement-breakpoint
CREATE UNIQUE INDEX `uniq_peer_base_url` ON `peers` (`base_url`);--> statement-breakpoint
CREATE TABLE `platform_health_state` (
	`source` text PRIMARY KEY NOT NULL,
	`consecutive_failures` integer DEFAULT 0 NOT NULL,
	`updated_at` integer DEFAULT (unixepoch()) NOT NULL
);
--> statement-breakpoint
CREATE TABLE `site_groups` (
	`id` text PRIMARY KEY NOT NULL,
	`slug` text NOT NULL,
	`name` text NOT NULL,
	`retention_days` integer DEFAULT 90 NOT NULL,
	`created_at` integer DEFAULT (unixepoch()) NOT NULL,
	`updated_at` integer DEFAULT (unixepoch()) NOT NULL
);
--> statement-breakpoint
CREATE UNIQUE INDEX `uniq_site_group_slug` ON `site_groups` (`slug`);