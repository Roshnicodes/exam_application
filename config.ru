# This file is used by Rack-based servers to start the application.

require_relative "config/environment"

# RAILS_RELATIVE_URL_ROOT=/exam_application serves the app under a sub-path
# (e.g. https://kra.asaindia.org/exam_application) next to another app on the same domain.
map ENV.fetch("RAILS_RELATIVE_URL_ROOT", "").presence || "/" do
  run Rails.application
end
Rails.application.load_server
