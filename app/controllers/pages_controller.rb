class PagesController < ApplicationController
  allow_unauthenticated_access only: :candidate_guide

  def guide
  end

  # Rules and warnings explained for candidates (shared with the test link, also as a PDF).
  def candidate_guide
    render layout: "exam"
  end
end
