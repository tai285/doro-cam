CREATE TYPE "public"."export_status" AS ENUM('pending', 'building', 'ready', 'failed');--> statement-breakpoint
ALTER TYPE "public"."asset_role" ADD VALUE 'video_web' BEFORE 'sanitized_original';--> statement-breakpoint
ALTER TYPE "public"."asset_role" ADD VALUE 'video_poster' BEFORE 'sanitized_original';--> statement-breakpoint
CREATE TABLE "data_exports" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"owner_id" uuid NOT NULL,
	"status" "export_status" DEFAULT 'pending' NOT NULL,
	"object_key" text,
	"bytes" bigint,
	"failure_reason" text,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"completed_at" timestamp with time zone,
	"expires_at" timestamp with time zone NOT NULL
);
--> statement-breakpoint
ALTER TABLE "data_exports" ADD CONSTRAINT "data_exports_owner_id_user_id_fk" FOREIGN KEY ("owner_id") REFERENCES "public"."user"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
CREATE INDEX "data_exports_owner_idx" ON "data_exports" USING btree ("owner_id");