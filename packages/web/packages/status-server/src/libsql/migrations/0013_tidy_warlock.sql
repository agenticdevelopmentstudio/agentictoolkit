ALTER TABLE `monitored_endpoints` ADD `monitor_http` integer DEFAULT true NOT NULL;--> statement-breakpoint
ALTER TABLE `monitored_endpoints` ADD `monitor_deploys` integer DEFAULT true NOT NULL;