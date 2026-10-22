class PagesController < ApplicationController
  allow_unauthenticated_access only: :candidate_guide

  def guide
    @lang = params[:lang] == "hi" ? "hi" : "en"
  end

  # Rules and warnings explained for candidates (shared with the test link, also as a PDF).
  def candidate_guide
    @lang = %w[en hi].include?(params[:lang]) ? params[:lang] : "both"
    render layout: "exam"
  end
end
