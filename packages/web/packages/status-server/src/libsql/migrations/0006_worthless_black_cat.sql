CREATE INDEX `idx_analytics_captured` ON `analytics_metrics` (`captured_at`);--> statement-breakpoint
CREATE INDEX `idx_metrics_hour` ON `metrics_hourly` (`hour`);