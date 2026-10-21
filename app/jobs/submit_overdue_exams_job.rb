# Every minute: submit tests whose time ran out but were never submitted (closed tab, lost connection),
# so they stop showing as "live" and get a result.
class SubmitOverdueExamsJob < ApplicationJob
  queue_as :default

  def perform
    Invitation.submit_overdue!
  end
end
