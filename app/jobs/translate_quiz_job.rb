# Auto-translates a question paper to Hindi in the background (several requests for a long paper).
class TranslateQuizJob < ApplicationJob
  queue_as :default

  def perform(quiz)
    Rails.cache.write(quiz.translation_key, true, expires_in: 30.minutes)
    count = HindiTranslator.new(quiz).translate!
    Rails.cache.write("quiz:#{quiz.id}:translation_result", "Translated #{count} questions to Hindi. Check them below.", expires_in: 1.day)
  rescue HindiTranslator::Error => e
    Rails.cache.write("quiz:#{quiz.id}:translation_result", "Hindi translation stopped: #{e.message}", expires_in: 1.day)
  ensure
    Rails.cache.delete(quiz.translation_key)
  end
end
