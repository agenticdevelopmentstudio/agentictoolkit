CREATE TABLE `analytics_metrics` (
	`id` integer PRIMARY KEY AUTOINCREMENT NOT NULL,
	`metric` text NOT NULL,
	`window` text NOT NULL,
	`scope` text DEFAULT 'all' NOT NULL,
	`value` integer NOT NULL,
	`captured_at` integer DEFAULT (unixepoch()) NOT NULL
);
--> statement-breakpoint
CREATE INDEX `idx_analytics_metric_time` ON `analytics_metrics` (`metric`,`window`,`scope`,`captured_at`);--> statement-breakpoint
CREATE TABLE `errors` (
	`id` text PRIMARY KEY NOT NULL,
	`issue_key` text NOT NULL,
	`project` text NOT NULL,
	`title` text NOT NULL,
	`culprit` text,
	`level` text,
	`count` integer DEFAULT 0 NOT NULL,
	`user_count` integer DEFAULT 0 NOT NULL,
	`first_seen` integer,
	`last_seen` integer,
	`permalink` text,
	`resolved` integer DEFAULT false NOT NULL,
	`fetched_at` integer DEFAULT (unixepoch()) NOT NULL
);
--> statement-breakpoint
CREATE UNIQUE INDEX `uniq_error_issue` ON `errors` (`issue_key`);--> statement-breakpoint
CREATE INDEX `idx_error_last_seen` ON `errors` (`last_seen`);--> statement-breakpoint
PRAGMA foreign_keys=OFF;--> statement-breakpoint
CREATE TABLE `__new_site_groups` (
	`id` text PRIMARY KEY NOT NULL,
	`slug` text NOT NULL,
	`name` text NOT NULL,
	`retention_days` integer DEFAULT 14 NOT NULL,
	`created_at` integer DEFAULT (unixepoch()) NOT NULL,
	`updated_at` integer DEFAULT (unixepoch()) NOT NULL
);
--> statement-breakpoint
INSERT INTO `__new_site_groups`("id", "slug", "name", "retention_days", "created_at", "updated_at") SELECT "id", "slug", "name", "retention_days", "created_at", "updated_at" FROM `site_groups`;--> statement-breakpoint
DROP TABLE `site_groups`;--> statement-breakpoint
ALTER TABLE `__new_site_groups` RENAME TO `site_groups`;--> statement-breakpoint
PRAGMA foreign_keys=ON;--> statement-breakpoint
CREATE UNIQUE INDEX `uniq_site_group_slug` ON `site_groups` (`slug`);