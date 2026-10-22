class ApplicationMailer < ActionMailer::Base
  default from: -> { ENV.fetch("SMTP_FROM") { ENV.fetch("SMTP_USERNAME", "no-reply@#{ENV.fetch('APP_HOST', 'example.com')}") } }
  layout "mailer"
end
