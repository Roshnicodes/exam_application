class ApplicationController < ActionController::Base
  include Authentication
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  rescue_from ActiveRecord::RecordNotFound, with: :record_not_found

  private
    # A deleted (or someone else's) record: go back to that section's list instead of an error page.
    def record_not_found
      respond_to do |format|
        format.html { redirect_to missing_record_fallback, alert: "That item no longer exists — it may have been deleted." }
        format.any { head :not_found }
      end
    end

    def missing_record_fallback
      url_for(controller: controller_name, action: :index)
    rescue ActionController::UrlGenerationError
      root_path
    end

    # One page of a long list (a relation or an array); sets @page, @pages, @total, @per for shared/_pager.
    def paginate(records, per: 50)
      @per = per
      @total = records.is_a?(Array) ? records.size : records.count
      @pages = [ (@total / per.to_f).ceil, 1 ].max
      @page = params[:page].to_i.clamp(1, @pages)
      offset = (@page - 1) * per
      records.is_a?(Array) ? records[offset, per] || [] : records.offset(offset).limit(per)
    end

    def send_xlsx(data, filename)
      send_data data, filename: filename, type: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
    end
end
