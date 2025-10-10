# frozen_string_literal: true

class MediaController < ApplicationController
  # Public: Proxy GET /media/*path to the protected S3 bucket (S3_BUCKET)
  # This endpoint is intended to be the origin for the CDN (Cloudflare).
  
  # Skip authentication - CDN will call this publicly. If you want to restrict
  # it to Cloudflare IPs, add a middleware or IP constraint.
  skip_before_action :require_authenticated_user, raise: false

  def show
    path = params[:path]
    return head :bad_request if path.blank?

    begin
      object = S3_BUCKET.object(path)

      # Check existence and permissions
      unless object.exists?
        return head :not_found
      end

      # Stream the object body
      resp = object.get

      # Set caching headers to encourage CDN caching
      response.headers["Cache-Control"] = "public, max-age=31536000, immutable"
      response.headers["ETag"] = resp.etag if resp.etag
      response.headers["Last-Modified"] = resp.last_modified.httpdate if resp.last_modified
      response.headers["Access-Control-Allow-Origin"] = "*"

      send_data resp.body.read, type: resp.content_type || "application/octet-stream", disposition: "inline"
    rescue Aws::S3::Errors::Forbidden
      head :forbidden
    rescue Aws::S3::Errors::NoSuchKey
      head :not_found
    rescue StandardError => e
      Rails.logger.error "[MediaController] Error proxying S3 object #{path}: #{e.class}: #{e.message}"
      head :internal_server_error
    end
  end
end
