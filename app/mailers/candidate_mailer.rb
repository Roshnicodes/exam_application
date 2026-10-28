# Test invitation to the candidate with the candidate guide PDF attached.
class CandidateMailer < ApplicationMailer
  helper ApplicationHelper

  # public/candidate-guide-<lang>.pdf, generated from /candidate-guide
  def self.guide_file(language)
    language == "hi" ? "candidate-guide-hi.pdf" : "candidate-guide-en.pdf"
  end

  def invitation(invitation)
    @invitation = invitation
    file = self.class.guide_file(invitation.language)
    attachments["ASA CHAYAN - Candidate Guide#{' (Hindi)' if invitation.hindi?}.pdf"] = File.binread(Rails.public_path.join(file))
    mail to: invitation.candidate_email, subject: "Online assessment – #{invitation.vacancy}"
  end

  def self.configured?
    Rails.env.development? || ENV["SMTP_ADDRESS"].present?
  end
end
