CREATE TABLE `vercel_prod_state` (
	`project_name` text PRIMARY KEY NOT NULL,
	`stale` integer DEFAULT false NOT NULL,
	`detail` text,
	`source_url` text,
	`live_url` text,
	`updated_at` integer DEFAULT (unixepoch()) NOT NULL
);
--> statement-breakpoint
ALTER TABLE `health_checks` ADD `dns_ok` integer DEFAULT true NOT NULL;--> statement-breakpoint
ALTER TABLE `issues` ADD `resolved_reason` text;--> statement-breakpoint
ALTER TABLE `platform_health_state` ADD `configured` integer DEFAULT true NOT NULL;--> statement-breakpoint
ALTER TABLE `platform_health_state` ADD `reachable` integer DEFAULT true NOT NULL;--> statement-breakpoint
-- `reachable` defaults to true, which is a lie for the only rows that matter: a platform
-- with a live failure streak was mid-outage when this migration ran. Without this, the
-- board suppresses that platform-health problem until the next poll rewrites the row.
UPDATE `platform_health_state` SET `reachable` = false WHERE `consecutive_failures` > 0;