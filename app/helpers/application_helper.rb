module ApplicationHelper
  # Lucide-style stroke icons (MIT), inlined so no icon font or CDN is needed.
  ICONS = {
    "home" => '<path d="m3 10 9-7 9 7v10a2 2 0 0 1-2 2h-4v-7H9v7H5a2 2 0 0 1-2-2z"/>',
    "users" => '<path d="M16 21v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2"/><circle cx="9" cy="7" r="4"/><path d="M22 21v-2a4 4 0 0 0-3-3.87M16 3.13a4 4 0 0 1 0 7.75"/>',
    "file" => '<path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z"/><path d="M14 2v6h6M16 13H8M16 17H8M10 9H8"/>',
    "plus" => '<path d="M12 5v14M5 12h14"/>',
    "camera" => '<path d="M14.5 4h-5L7 7H4a2 2 0 0 0-2 2v9a2 2 0 0 0 2 2h16a2 2 0 0 0 2-2V9a2 2 0 0 0-2-2h-3z"/><circle cx="12" cy="13" r="3"/>',
    "video" => '<path d="m22 8-6 4 6 4V8z"/><rect x="2" y="6" width="14" height="12" rx="2"/>',
    "shield" => '<path d="M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z"/><path d="m9 12 2 2 4-4"/>',
    "alert" => '<path d="m21.73 18-8-14a2 2 0 0 0-3.48 0l-8 14A2 2 0 0 0 4 21h16a2 2 0 0 0 1.73-3"/><path d="M12 9v4M12 17h.01"/>',
    "check" => '<path d="M20 6 9 17l-5-5"/>',
    "check-circle" => '<circle cx="12" cy="12" r="10"/><path d="m9 12 2 2 4-4"/>',
    "x" => '<path d="M18 6 6 18M6 6l12 12"/>',
    "x-circle" => '<circle cx="12" cy="12" r="10"/><path d="m15 9-6 6M9 9l6 6"/>',
    "clock" => '<circle cx="12" cy="12" r="10"/><path d="M12 6v6l4 2"/>',
    "phone" => '<path d="M22 16.92v3a2 2 0 0 1-2.18 2 19.8 19.8 0 0 1-8.63-3.07 19.5 19.5 0 0 1-6-6A19.8 19.8 0 0 1 2.12 4.18 2 2 0 0 1 4.11 2h3a2 2 0 0 1 2 1.72c.13.96.36 1.9.7 2.81a2 2 0 0 1-.45 2.11L8.09 9.91a16 16 0 0 0 6 6l1.27-1.27a2 2 0 0 1 2.11-.45c.91.34 1.85.57 2.81.7A2 2 0 0 1 22 16.92z"/>',
    "link" => '<path d="M10 13a5 5 0 0 0 7.54.54l3-3a5 5 0 0 0-7.07-7.07l-1.72 1.71"/><path d="M14 11a5 5 0 0 0-7.54-.54l-3 3a5 5 0 0 0 7.07 7.07l1.71-1.71"/>',
    "copy" => '<rect x="9" y="9" width="13" height="13" rx="2"/><path d="M5 15H4a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h9a2 2 0 0 1 2 2v1"/>',
    "bell" => '<path d="M6 8a6 6 0 0 1 12 0c0 7 3 9 3 9H3s3-2 3-9"/><path d="M10.3 21a1.94 1.94 0 0 0 3.4 0"/>',
    "logout" => '<path d="M9 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h4M16 17l5-5-5-5M21 12H9"/>',
    "calendar" => '<rect x="3" y="4" width="18" height="18" rx="2"/><path d="M16 2v4M8 2v4M3 10h18"/>',
    "briefcase" => '<rect x="2" y="7" width="20" height="14" rx="2"/><path d="M16 21V5a2 2 0 0 0-2-2h-4a2 2 0 0 0-2 2v16"/>',
    "mail" => '<rect x="2" y="4" width="20" height="16" rx="2"/><path d="m22 7-10 6L2 7"/>',
    "eye" => '<path d="M2 12s3-7 10-7 10 7 10 7-3 7-10 7-10-7-10-7z"/><circle cx="12" cy="12" r="3"/>',
    "trash" => '<path d="M3 6h18M19 6v14a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V6M8 6V4a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2"/>',
    "edit" => '<path d="M12 20h9M16.5 3.5a2.12 2.12 0 0 1 3 3L7 19l-4 1 1-4z"/>',
    "chevron-right" => '<path d="m9 18 6-6-6-6"/>',
    "chevron-left" => '<path d="m15 18-6-6 6-6"/>',
    "arrow-left" => '<path d="M19 12H5M12 19l-7-7 7-7"/>',
    "arrow-right" => '<path d="M5 12h14M12 5l7 7-7 7"/>',
    "play" => '<path d="m6 3 14 9-14 9z"/>',
    "award" => '<circle cx="12" cy="8" r="6"/><path d="M15.48 12.89 17 22l-5-3-5 3 1.52-9.11"/>',
    "volume" => '<path d="M11 5 6 9H2v6h4l5 4zM15.54 8.46a5 5 0 0 1 0 7.07M19.07 4.93a10 10 0 0 1 0 14.14"/>',
    "volume-off" => '<path d="M11 5 6 9H2v6h4l5 4zM22 9l-6 6M16 9l6 6"/>',
    "menu" => '<path d="M4 6h16M4 12h16M4 18h16"/>',
    "flag" => '<path d="M4 15s1-1 4-1 5 2 8 2 4-1 4-1V3s-1 1-4 1-5-2-8-2-4 1-4 1zM4 22v-7"/>',
    "send" => '<path d="m22 2-7 20-4-9-9-4zM22 2 11 13"/>',
    "lock" => '<rect x="3" y="11" width="18" height="11" rx="2"/><path d="M7 11V7a5 5 0 0 1 10 0v4"/>',
    "maximize" => '<path d="M8 3H5a2 2 0 0 0-2 2v3M21 8V5a2 2 0 0 0-2-2h-3M3 16v3a2 2 0 0 0 2 2h3M16 21h3a2 2 0 0 0 2-2v-3"/>',
    "mic" => '<rect x="9" y="2" width="6" height="12" rx="3"/><path d="M19 10v2a7 7 0 0 1-14 0v-2M12 19v3"/>',
    "monitor" => '<rect x="2" y="3" width="20" height="14" rx="2"/><path d="M8 21h8M12 17v4"/>',
    "wifi" => '<path d="M5 12.55a11 11 0 0 1 14.08 0M1.42 9a16 16 0 0 1 21.16 0M8.53 16.11a6 6 0 0 1 6.95 0M12 20h.01"/>',
    "map" => '<path d="M20 10c0 6-8 12-8 12s-8-6-8-12a8 8 0 0 1 16 0z"/><circle cx="12" cy="10" r="3"/>',
    "search" => '<circle cx="11" cy="11" r="8"/><path d="m21 21-4.3-4.3"/>',
    "activity" => '<path d="M22 12h-4l-3 9L9 3l-3 9H2"/>',
    "sparkles" => '<path d="m12 3-1.9 5.8a2 2 0 0 1-1.3 1.3L3 12l5.8 1.9a2 2 0 0 1 1.3 1.3L12 21l1.9-5.8a2 2 0 0 1 1.3-1.3L21 12l-5.8-1.9a2 2 0 0 1-1.3-1.3z"/>',
    "whatsapp" => '<path d="M3 21l1.65-3.8a9 9 0 1 1 3.4 2.9z"/><path d="M9 10a.5.5 0 0 0 1 0V9a.5.5 0 0 0-1 0v1a5 5 0 0 0 5 5h1a.5.5 0 0 0 0-1h-1a.5.5 0 0 0 0 1"/>',
    "list" => '<path d="M8 6h13M8 12h13M8 18h13M3 6h.01M3 12h.01M3 18h.01"/>',
    "user" => '<circle cx="12" cy="8" r="5"/><path d="M20 21a8 8 0 0 0-16 0"/>',
    "upload" => '<path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4M17 8l-5-5-5 5M12 3v12"/>',
    "download" => '<path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4M7 10l5 5 5-5M12 15V3"/>',
    "building" => '<rect x="4" y="2" width="16" height="20" rx="2"/><path d="M9 22v-4h6v4M8 6h.01M16 6h.01M12 6h.01M12 10h.01M12 14h.01M16 10h.01M16 14h.01M8 10h.01M8 14h.01"/>',
    "sheet" => '<path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z"/><path d="M14 2v6h6M8 13h8M8 17h8M12 13v8"/>',
    "id-card" => '<rect x="2" y="5" width="20" height="14" rx="2"/><circle cx="8" cy="12" r="2"/><path d="M14 10h4M14 14h4"/>',
    "graduation" => '<path d="M22 10 12 5 2 10l10 5 10-5z"/><path d="M6 12v5c3 3 9 3 12 0v-5"/>',
    "target" => '<circle cx="12" cy="12" r="10"/><circle cx="12" cy="12" r="6"/><circle cx="12" cy="12" r="2"/>',
    "key" => '<circle cx="7.5" cy="15.5" r="5.5"/><path d="m21 2-9.6 9.6M15.5 7.5l3 3L22 7l-3-3"/>',
    "leaf" => '<path d="M11 20A7 7 0 0 1 9.8 6.1C15.5 5 17 4.48 19 2c1 2 2 4.18 2 8 0 5.5-4.78 10-10 10Z"/><path d="M2 21c0-3 1.85-5.36 5.08-6C9.5 14.52 12 13 13 12"/>',
    "chevron-down" => '<path d="m6 9 6 6 6-6"/>',
    "code" => '<path d="m16 18 6-6-6-6M8 6l-6 6 6 6"/>',
    "unlock" => '<rect x="3" y="11" width="18" height="11" rx="2"/><path d="M7 11V7a5 5 0 0 1 9.9-1"/>',
    "message" => '<path d="M21 15a2 2 0 0 1-2 2H7l-4 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2z"/>',
    "arrow-up" => '<path d="M12 19V5M5 12l7-7 7 7"/>',
    "arrow-down" => '<path d="M12 5v14M19 12l-7 7-7-7"/>',
    "trending-up" => '<path d="m22 7-8.5 8.5-5-5L2 17"/><path d="M16 7h6v6"/>',
    "trending-down" => '<path d="m22 17-8.5-8.5-5 5L2 7"/><path d="M16 17h6v-6"/>',
    "more" => '<circle cx="12" cy="5" r="1"/><circle cx="12" cy="12" r="1"/><circle cx="12" cy="19" r="1"/>'
  }.freeze

  def icon(name, css: nil)
    tag.svg(ICONS.fetch(name.to_s, ICONS["sparkles"]).html_safe, class: [ "icon", css ].compact.join(" "),
            viewBox: "0 0 24 24", "aria-hidden": "true")
  end

  def status_badge(invitation)
    key = invitation.link_expired? ? "expired" : invitation.status
    tag.span(class: "badge badge-#{key}") { tag.span(class: "dot") + invitation.status_label }
  end

  EVENT_ICONS = {
    "tab_switch" => "monitor", "window_blur" => "eye", "fullscreen_exit" => "maximize", "no_face" => "user",
    "multiple_faces" => "users", "looking_away" => "eye", "eyes_away" => "eye", "phone_detected" => "phone", "screen_share_stopped" => "monitor", "screen_not_entire" => "monitor", "face_movement" => "activity", "camera_off" => "camera", "copy_paste" => "copy", "right_click" => "lock",
    "devtools" => "alert", "screenshot" => "camera", "window_resize" => "monitor", "noise" => "mic",
    "multiple_displays" => "monitor", "otp_requested" => "key", "otp_failed" => "x-circle", "verified" => "shield",
    "exam_started" => "play", "exam_submitted" => "check-circle", "exam_terminated" => "x-circle",
    "time_up" => "clock", "snapshot" => "camera", "detector_unavailable" => "alert"
  }.freeze

  def event_icon(event)
    tag.span(icon(EVENT_ICONS.fetch(event.kind, "activity")), class: "t-ico sev-#{event.severity}")
  end

  def nav_link(label, path, icon_name, active: current_page?(path), count: nil)
    link_to path, class: ("active" if active) do
      safe_join([ icon(icon_name), label, (tag.span(count, class: "count") if count.to_i.positive?) ].compact)
    end
  end

  # Small trend line (with a soft filled area) for the dashboard stat cards.
  def sparkline(values, width: 96, height: 36)
    max = [ values.max.to_i, 1 ].max
    step = width.to_f / [ values.size - 1, 1 ].max
    points = values.each_with_index.map { |v, i| [ (i * step).round(1), (height - 3 - v.to_f / max * (height - 8)).round(1) ] }
    line = points.map { |x, y| "#{x},#{y}" }.join(" ")
    area = "0,#{height} #{line} #{width},#{height}"
    tag.svg(class: "spark", viewBox: "0 0 #{width} #{height}", preserveAspectRatio: "none", "aria-hidden": true) do
      tag.polygon(points: area, class: "spark-area") + tag.polyline(points: line, class: "spark-line")
    end
  end

  PARAM_COLORS = %w[#6366f1 #ec4899 #10b981 #f59e0b #3b82f6 #8b5cf6 #ef4444 #14b8a6].freeze

  def param_color(i)
    PARAM_COLORS[i % PARAM_COLORS.size]
  end

  def vacancy_status_badge(vacancy)
    tag.span(vacancy.status.capitalize, class: "badge status-#{vacancy.status}")
  end

  # Stable, colourful gradient per text (same department / person always gets the same colours).
  GRADIENTS = [
    %w[#6366f1 #a855f7], %w[#ec4899 #f43f5e], %w[#f59e0b #f97316], %w[#10b981 #14b8a6], %w[#3b82f6 #06b6d4],
    %w[#8b5cf6 #ec4899], %w[#ef4444 #f59e0b], %w[#0ea5e9 #6366f1], %w[#22c55e #84cc16], %w[#d946ef #8b5cf6]
  ].freeze

  def gradient_for(text)
    a, b = GRADIENTS[Zlib.crc32(text.to_s.downcase) % GRADIENTS.size]
    "linear-gradient(135deg, #{a}, #{b})"
  end

  def tint_for(text)
    GRADIENTS[Zlib.crc32(text.to_s.downcase) % GRADIENTS.size].first
  end

  # Opens WhatsApp straight on the person's chat: WhatsApp Web in one reused tab on a computer,
  # the WhatsApp app on a phone (see whatsapp_controller.js).
  # Indian 10-digit numbers get the 91 prefix. Without a number the button asks for one.
  def whatsapp_button(phone, text, label: "WhatsApp", css: "btn btn-light btn-sm", title: nil)
    digits = phone.to_s.gsub(/\D/, "")
    digits = "91#{digits}" if digits.length == 10
    content = safe_join([ icon("whatsapp"), (" #{label}" if label.present?) ].compact)
    if digits.length >= 11
      link_to content, "https://api.whatsapp.com/send?#{{ phone: digits, text: text }.to_query}",
              class: css, target: "_blank", rel: "noopener", title: title || "WhatsApp +#{digits}",
              data: { controller: "whatsapp", action: "whatsapp#open", whatsapp_text_value: text, whatsapp_phone_value: digits }
    else
      button_tag content, type: "button", class: css, title: title || "WhatsApp (asks for the number)",
                 data: { controller: "whatsapp", action: "whatsapp#open", whatsapp_text_value: text }
    end
  end

  def candidate_share_text(invitation)
    "Hi #{invitation.candidate_name}, please take your online assessment for the #{invitation.vacancy} role here: " \
      "#{exam_url(invitation.token)} (Your HR will share the OTP with you.)" +
      (invitation.meeting_link.present? ? " Interview meeting link: #{invitation.meeting_link}" : "")
  end

  def panelist_share_text(employee, invitation: nil, batch: nil)
    what = invitation ? "#{invitation.candidate_name}'s exam (#{invitation.vacancy})" : "the \"#{batch.name}\" group exam"
    link = invitation ? watch_url(invitation.watch_token) : watch_batch_url(batch.watch_token)
    "Hi #{employee.name}, you are on the interview panel for #{what}. Watch the candidate's live camera here: #{link}"
  end

  def decision_message(invitation)
    case invitation.decision
    when "selected" then "Congratulations #{invitation.candidate_name}! 🎉 You have been selected for the #{invitation.vacancy} role. Our HR team will share the next steps shortly."
    when "on_hold" then "Hi #{invitation.candidate_name}, thank you for interviewing for the #{invitation.vacancy} role. Your application is currently on hold; we will get back to you soon."
    when "rejected" then "Hi #{invitation.candidate_name}, thank you for your time and interest in the #{invitation.vacancy} role. We will not be moving forward this time, and we wish you all the best."
    end.to_s
  end

  # WebRTC servers for live video / interviews. Public STUN always; our TURN relay when configured:
  #   TURN_URLS="turn:64.227.162.55:3478,turn:64.227.162.55:3478?transport=tcp"
  #   TURN_SECRET=<coturn static-auth-secret>  -> short-lived credentials (12 h), or
  #   TURN_USERNAME / TURN_PASSWORD             -> fixed credentials
  def ice_servers
    servers = [ { urls: %w[stun:stun.l.google.com:19302 stun:stun.cloudflare.com:3478] } ]
    urls = ENV["TURN_URLS"].to_s.split(",").map(&:strip).compact_blank
    return servers if urls.empty?

    if ENV["TURN_SECRET"].present?
      username = "#{12.hours.from_now.to_i}:hireproctor"
      credential = Base64.strict_encode64(OpenSSL::HMAC.digest("sha1", ENV["TURN_SECRET"], username))
      servers << { urls: urls, username: username, credential: credential }
    else
      servers << { urls: urls, username: ENV["TURN_USERNAME"], credential: ENV["TURN_PASSWORD"] }
    end
  end

  def initials_for(name)
    name.to_s.split.map(&:first).first(2).join.upcase.presence || "?"
  end

  def nice_time(time)
    return "—" unless time

    time.to_date == Date.current ? "Today, #{time.strftime('%-I:%M %p')}" : time.strftime("%d %b %Y, %-I:%M %p")
  end

  def duration_between(from, to)
    return "—" unless from && to

    secs = (to - from).to_i
    format("%dm %02ds", secs / 60, secs % 60)
  end
end
