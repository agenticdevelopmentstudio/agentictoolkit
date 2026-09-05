ALTER TABLE `monitored_endpoints` ADD `dns_check_a` integer DEFAULT true NOT NULL;--> statement-breakpoint
ALTER TABLE `monitored_endpoints` ADD `dns_check_aaaa` integer DEFAULT true NOT NULL;--> statement-breakpoint
ALTER TABLE `monitored_endpoints` ADD `dns_check_cname` integer DEFAULT true NOT NULL;