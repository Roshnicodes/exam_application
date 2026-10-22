class ProctorEvent < ApplicationRecord
  # kind => [label, severity, counts as a warning?]
  KINDS = {
    "tab_switch"        => [ "Switched tab / minimized window", "high", true ],
    "window_blur"       => [ "Exam window lost focus", "medium", true ],
    "fullscreen_exit"   => [ "Exited full screen mode", "medium", true ],
    "no_face"           => [ "No face visible in camera", "high", true ],
    "multiple_faces"    => [ "Multiple faces detected", "critical", true ],
    "looking_away"      => [ "Looking away from the screen", "medium", true ],
    "eyes_away"         => [ "Eyes off screen (looking down / away)", "high", true ],
    "phone_detected"    => [ "Mobile phone / book / device detected", "critical", true ],
    "screen_share_stopped" => [ "Stopped sharing the screen", "high", true ],
    "screen_not_entire" => [ "Shared a window instead of the entire screen", "medium", true ],
    "face_movement"     => [ "Excessive movement / out of camera frame", "medium", true ],
    "camera_off"        => [ "Camera stopped or blocked", "critical", true ],
    "copy_paste"        => [ "Copy / paste attempt", "medium", true ],
    "right_click"       => [ "Right click attempt", "low", true ],
    "devtools"          => [ "Restricted shortcut / developer tools", "high", true ],
    "screenshot"        => [ "Screenshot attempt", "high", true ],
    "window_resize"     => [ "Window resized / split screen", "medium", true ],
    "noise"             => [ "Voice or loud background noise", "low", true ],
    "multiple_displays" => [ "Multiple displays connected", "high", true ],
    "otp_requested"     => [ "Candidate requested OTP", "info", false ],
    "otp_failed"        => [ "Wrong OTP entered", "medium", false ],
    "verified"          => [ "Candidate verified with OTP", "info", false ],
    "exam_started"      => [ "Exam started", "info", false ],
    "exam_submitted"    => [ "Exam submitted", "success", false ],
    "exam_terminated"   => [ "Exam ended early (terminated / removed)", "critical", false ],
    "time_up"           => [ "Time is up - auto submitted", "info", false ],
    "snapshot"          => [ "Periodic camera snapshot", "info", false ],
    "detector_unavailable" => [ "Face detection unavailable on candidate device", "medium", false ],
    "screen_share_unavailable" => [ "Screen sharing not possible on this device (phone / tablet)", "info", false ],
    "switching_allowed" => [ "Panel allowed switching apps (e.g. an online editor)", "info", false ],
    "switching_blocked" => [ "Panel turned app-switching checks back on", "info", false ],
    "call_ended"        => [ "Video call ended for everyone", "info", false ]
  }.freeze

  ALERT_KINDS = (KINDS.select { |_, v| v[2] }.keys + %w[otp_requested otp_failed exam_started exam_submitted exam_terminated time_up detector_unavailable]).freeze

  belongs_to :invitation
  has_one_attached :snapshot

  validates :kind, inclusion: { in: KINDS.keys }

  before_validation { self.severity = KINDS.dig(kind, 1) || "info" if severity.blank? || severity == "warning" }

  scope :violations, -> { where(kind: KINDS.select { |_, v| v[2] }.keys) }
  scope :for_round, ->(round) { where("metadata ->> 'round_id' = ?", round.id.to_s) }
  scope :timeline, -> { where.not(kind: "snapshot").order(created_at: :desc) }
  scope :with_snapshots, -> { joins(:snapshot_attachment) }

  after_create_commit :broadcast_to_hr

  def label
    KINDS.dig(kind, 0) || kind.humanize
  end

  def violation?
    KINDS.dig(kind, 2) == true
  end

  def alert?
    ALERT_KINDS.include?(kind)
  end

  private
    def broadcast_to_hr
      invitation.broadcast_tile
      return if kind == "snapshot"

      broadcast_prepend_to [ invitation, :events ], target: "events_invitation_#{invitation_id}",
                           partial: "proctor_events/proctor_event", locals: { proctor_event: self }
      HrAlertsChannel.notify(self) if alert?
    end
end
