# Settings for running under a sub-path (RAILS_RELATIVE_URL_ROOT), e.g. /exam_application.
# The login + session cookies get their own names and that path, so another Rails app
# on the same domain can't overwrite them (and vice versa).
APP_ROOT_PATH = ENV["RAILS_RELATIVE_URL_ROOT"].to_s.chomp("/").presence
AUTH_COOKIE = :exam_session_id

Rails.application.config.session_store :cookie_store, key: "_exam_application_session", path: APP_ROOT_PATH || "/"

if APP_ROOT_PATH
  # URLs built outside a request (live broadcasts, alert payloads) need the prefix too;
  # ApplicationController.renderer picks script_name up from these defaults.
  Rails.application.routes.default_url_options[:script_name] = APP_ROOT_PATH
end
