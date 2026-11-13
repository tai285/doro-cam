CREATE TYPE "public"."asset_role" AS ENUM('photo_original', 'photo_rendered', 'photo_display', 'thumbnail', 'motion_clip', 'motion_web', 'video_original', 'sanitized_original');--> statement-breakpoint
CREATE TYPE "public"."asset_status" AS ENUM('pending', 'uploading', 'uploaded', 'verified', 'ready', 'failed');--> statement-breakpoint
CREATE TYPE "public"."change_entity" AS ENUM('memory', 'asset', 'preset', 'album');--> statement-breakpoint
CREATE TYPE "public"."change_op" AS ENUM('upsert', 'delete');--> statement-breakpoint
CREATE TYPE "public"."lens_kind" AS ENUM('ultraWide', 'wide', 'tele', 'front', 'other');--> statement-breakpoint
CREATE TYPE "public"."memory_kind" AS ENUM('photo', 'motion', 'video');--> statement-breakpoint
CREATE TYPE "public"."preset_source" AS ENUM('user', 'suggested');--> statement-breakpoint
CREATE TYPE "public"."album_kind" AS ENUM('album', 'trip');--> statement-breakpoint
CREATE TYPE "public"."album_role" AS ENUM('owner', 'editor', 'contributor', 'viewer');--> statement-breakpoint
CREATE SEQUENCE "public"."change_seq" INCREMENT BY 1 MINVALUE 1 MAXVALUE 9223372036854775807 START WITH 1 CACHE 1;--> statement-breakpoint
CREATE TABLE "account" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"account_id" text NOT NULL,
	"provider_id" text NOT NULL,
	"user_id" uuid NOT NULL,
	"access_token" text,
	"refresh_token" text,
	"id_token" text,
	"access_token_expires_at" timestamp with time zone,
	"refresh_token_expires_at" timestamp with time zone,
	"scope" text,
	"password" text,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "session" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"expires_at" timestamp with time zone NOT NULL,
	"token" text NOT NULL,
	"ip_address" text,
	"user_agent" text,
	"user_id" uuid NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "session_token_unique" UNIQUE("token")
);
--> statement-breakpoint
CREATE TABLE "user" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"name" text NOT NULL,
	"email" text NOT NULL,
	"email_verified" boolean DEFAULT false NOT NULL,
	"image" text,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "user_email_unique" UNIQUE("email")
);
--> statement-breakpoint
CREATE TABLE "users_profile" (
	"user_id" uuid PRIMARY KEY NOT NULL,
	"storage_bytes" bigint DEFAULT 0 NOT NULL,
	"deletion_requested_at" timestamp with time zone,
	"settings" jsonb DEFAULT '{}'::jsonb NOT NULL
);
--> statement-breakpoint
CREATE TABLE "verification" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"identifier" text NOT NULL,
	"value" text NOT NULL,
	"expires_at" timestamp with time zone NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "assets" (
	"id" uuid PRIMARY KEY NOT NULL,
	"memory_id" uuid NOT NULL,
	"owner_id" uuid NOT NULL,
	"role" "asset_role" NOT NULL,
	"status" "asset_status" DEFAULT 'pending' NOT NULL,
	"failure_reason" text,
	"mime" text NOT NULL,
	"bytes" bigint NOT NULL,
	"sha256" "bytea" NOT NULL,
	"width" integer,
	"height" integer,
	"duration_ms" integer,
	"storage_object_id" uuid,
	"upload_id" text,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "change_log" (
	"seq" bigint PRIMARY KEY NOT NULL,
	"owner_id" uuid NOT NULL,
	"entity" "change_entity" NOT NULL,
	"entity_id" uuid NOT NULL,
	"op" "change_op" NOT NULL,
	"at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "idempotency_keys" (
	"key" text NOT NULL,
	"owner_id" uuid NOT NULL,
	"route" text NOT NULL,
	"request_hash" text NOT NULL,
	"status_code" integer NOT NULL,
	"response" jsonb NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "idempotency_keys_owner_id_key_pk" PRIMARY KEY("owner_id","key")
);
--> statement-breakpoint
CREATE TABLE "memories" (
	"id" uuid PRIMARY KEY NOT NULL,
	"owner_id" uuid NOT NULL,
	"kind" "memory_kind" NOT NULL,
	"captured_at" timestamp with time zone NOT NULL,
	"captured_tz" text NOT NULL,
	"experience_id" text NOT NULL,
	"profile_id" text,
	"profile_version" integer,
	"preset_id" uuid,
	"scenario" text,
	"focal_length_35mm" real,
	"iso" integer,
	"exposure_time_ns" bigint,
	"aperture" real,
	"lens_kind" "lens_kind",
	"capture" jsonb NOT NULL,
	"lat" double precision,
	"lon" double precision,
	"location_accuracy_m" real,
	"location_shared" boolean DEFAULT false NOT NULL,
	"caption" text,
	"favorite" boolean DEFAULT false NOT NULL,
	"aspect_ratio" text,
	"public_handle" text NOT NULL,
	"version" integer DEFAULT 1 NOT NULL,
	"change_seq" bigint NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL,
	"deleted_at" timestamp with time zone,
	CONSTRAINT "memories_public_handle_unique" UNIQUE("public_handle"),
	CONSTRAINT "memories_location_both_or_neither" CHECK (("memories"."lat" is null) = ("memories"."lon" is null)),
	CONSTRAINT "memories_caption_len" CHECK ("memories"."caption" is null or char_length("memories"."caption") <= 2000)
);
--> statement-breakpoint
CREATE TABLE "storage_objects" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"owner_id" uuid NOT NULL,
	"key" text NOT NULL,
	"bytes" bigint NOT NULL,
	"sha256" "bytea" NOT NULL,
	"ref_count" integer DEFAULT 0 NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "storage_objects_key_unique" UNIQUE("key"),
	CONSTRAINT "storage_objects_owner_hash_uq" UNIQUE("owner_id","sha256","bytes")
);
--> statement-breakpoint
CREATE TABLE "preset_suggestion_dismissals" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"owner_id" uuid NOT NULL,
	"pattern_key" text NOT NULL,
	"dismissed_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "presets" (
	"id" uuid PRIMARY KEY NOT NULL,
	"owner_id" uuid NOT NULL,
	"name" text NOT NULL,
	"experience_id" text NOT NULL,
	"intent" jsonb NOT NULL,
	"profile_id" text,
	"profile_version" integer,
	"live" boolean DEFAULT false NOT NULL,
	"source" "preset_source" DEFAULT 'user' NOT NULL,
	"version" integer DEFAULT 1 NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL,
	"deleted_at" timestamp with time zone
);
--> statement-breakpoint
CREATE TABLE "album_invites" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"album_id" uuid NOT NULL,
	"role" "album_role" NOT NULL,
	"token_hash" text NOT NULL,
	"created_by" uuid NOT NULL,
	"expires_at" timestamp with time zone NOT NULL,
	"max_uses" integer DEFAULT 1 NOT NULL,
	"uses" integer DEFAULT 0 NOT NULL,
	"revoked_at" timestamp with time zone,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "album_invites_token_hash_unique" UNIQUE("token_hash")
);
--> statement-breakpoint
CREATE TABLE "album_items" (
	"album_id" uuid NOT NULL,
	"memory_id" uuid NOT NULL,
	"added_by" uuid NOT NULL,
	"added_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "album_items_album_id_memory_id_pk" PRIMARY KEY("album_id","memory_id")
);
--> statement-breakpoint
CREATE TABLE "album_members" (
	"album_id" uuid NOT NULL,
	"user_id" uuid NOT NULL,
	"role" "album_role" NOT NULL,
	"invited_by" uuid,
	"joined_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "album_members_album_id_user_id_pk" PRIMARY KEY("album_id","user_id")
);
--> statement-breakpoint
CREATE TABLE "albums" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"owner_id" uuid NOT NULL,
	"kind" "album_kind" DEFAULT 'album' NOT NULL,
	"title" text NOT NULL,
	"description" text,
	"starts_on" date,
	"ends_on" date,
	"cover_memory_id" uuid,
	"allow_original_download" boolean DEFAULT true NOT NULL,
	"share_location" boolean DEFAULT false NOT NULL,
	"auto_add_during_trip" boolean DEFAULT false NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL,
	"deleted_at" timestamp with time zone
);
--> statement-breakpoint
ALTER TABLE "account" ADD CONSTRAINT "account_user_id_user_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."user"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "session" ADD CONSTRAINT "session_user_id_user_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."user"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "users_profile" ADD CONSTRAINT "users_profile_user_id_user_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."user"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "assets" ADD CONSTRAINT "assets_memory_id_memories_id_fk" FOREIGN KEY ("memory_id") REFERENCES "public"."memories"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "assets" ADD CONSTRAINT "assets_owner_id_user_id_fk" FOREIGN KEY ("owner_id") REFERENCES "public"."user"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "assets" ADD CONSTRAINT "assets_storage_object_id_storage_objects_id_fk" FOREIGN KEY ("storage_object_id") REFERENCES "public"."storage_objects"("id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "change_log" ADD CONSTRAINT "change_log_owner_id_user_id_fk" FOREIGN KEY ("owner_id") REFERENCES "public"."user"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "idempotency_keys" ADD CONSTRAINT "idempotency_keys_owner_id_user_id_fk" FOREIGN KEY ("owner_id") REFERENCES "public"."user"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "memories" ADD CONSTRAINT "memories_owner_id_user_id_fk" FOREIGN KEY ("owner_id") REFERENCES "public"."user"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "storage_objects" ADD CONSTRAINT "storage_objects_owner_id_user_id_fk" FOREIGN KEY ("owner_id") REFERENCES "public"."user"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "preset_suggestion_dismissals" ADD CONSTRAINT "preset_suggestion_dismissals_owner_id_user_id_fk" FOREIGN KEY ("owner_id") REFERENCES "public"."user"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "presets" ADD CONSTRAINT "presets_owner_id_user_id_fk" FOREIGN KEY ("owner_id") REFERENCES "public"."user"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "album_invites" ADD CONSTRAINT "album_invites_album_id_albums_id_fk" FOREIGN KEY ("album_id") REFERENCES "public"."albums"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "album_invites" ADD CONSTRAINT "album_invites_created_by_user_id_fk" FOREIGN KEY ("created_by") REFERENCES "public"."user"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "album_items" ADD CONSTRAINT "album_items_album_id_albums_id_fk" FOREIGN KEY ("album_id") REFERENCES "public"."albums"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "album_items" ADD CONSTRAINT "album_items_memory_id_memories_id_fk" FOREIGN KEY ("memory_id") REFERENCES "public"."memories"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "album_items" ADD CONSTRAINT "album_items_added_by_user_id_fk" FOREIGN KEY ("added_by") REFERENCES "public"."user"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "album_members" ADD CONSTRAINT "album_members_album_id_albums_id_fk" FOREIGN KEY ("album_id") REFERENCES "public"."albums"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "album_members" ADD CONSTRAINT "album_members_user_id_user_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."user"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "album_members" ADD CONSTRAINT "album_members_invited_by_user_id_fk" FOREIGN KEY ("invited_by") REFERENCES "public"."user"("id") ON DELETE set null ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "albums" ADD CONSTRAINT "albums_owner_id_user_id_fk" FOREIGN KEY ("owner_id") REFERENCES "public"."user"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "albums" ADD CONSTRAINT "albums_cover_memory_id_memories_id_fk" FOREIGN KEY ("cover_memory_id") REFERENCES "public"."memories"("id") ON DELETE set null ON UPDATE no action;--> statement-breakpoint
CREATE INDEX "account_user_id_idx" ON "account" USING btree ("user_id");--> statement-breakpoint
CREATE INDEX "session_user_id_idx" ON "session" USING btree ("user_id");--> statement-breakpoint
CREATE INDEX "verification_identifier_idx" ON "verification" USING btree ("identifier");--> statement-breakpoint
CREATE INDEX "assets_memory_idx" ON "assets" USING btree ("memory_id");--> statement-breakpoint
CREATE INDEX "assets_owner_idx" ON "assets" USING btree ("owner_id");--> statement-breakpoint
CREATE INDEX "assets_storage_object_idx" ON "assets" USING btree ("storage_object_id");--> statement-breakpoint
CREATE UNIQUE INDEX "assets_memory_role_uq" ON "assets" USING btree ("memory_id","role");--> statement-breakpoint
CREATE INDEX "change_log_owner_seq_idx" ON "change_log" USING btree ("owner_id","seq");--> statement-breakpoint
CREATE INDEX "memories_library_idx" ON "memories" USING btree ("owner_id","captured_at" DESC NULLS LAST,"id");--> statement-breakpoint
CREATE INDEX "memories_sync_idx" ON "memories" USING btree ("owner_id","change_seq");--> statement-breakpoint
CREATE INDEX "memories_trash_idx" ON "memories" USING btree ("deleted_at") WHERE "memories"."deleted_at" is not null;--> statement-breakpoint
CREATE UNIQUE INDEX "preset_dismissals_owner_pattern_uq" ON "preset_suggestion_dismissals" USING btree ("owner_id","pattern_key");--> statement-breakpoint
CREATE INDEX "presets_owner_idx" ON "presets" USING btree ("owner_id");--> statement-breakpoint
CREATE INDEX "album_invites_album_idx" ON "album_invites" USING btree ("album_id");--> statement-breakpoint
CREATE INDEX "album_items_memory_idx" ON "album_items" USING btree ("memory_id");--> statement-breakpoint
CREATE INDEX "album_members_user_idx" ON "album_members" USING btree ("user_id");--> statement-breakpoint
CREATE INDEX "albums_owner_idx" ON "albums" USING btree ("owner_id");