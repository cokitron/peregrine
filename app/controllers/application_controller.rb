class ApplicationController < ActionController::Base
  allow_browser versions: :modern
  stale_when_importmap_changes

  layout "authenticated"

  rescue_from ActiveRecord::RecordNotFound, with: :not_found

  private

  def not_found
    respond_to do |format|
      format.html { render file: Rails.public_path.join("404.html"), status: :not_found, layout: false }
      format.json { render json: { error: "Not found" }, status: :not_found }
    end
  end
end
