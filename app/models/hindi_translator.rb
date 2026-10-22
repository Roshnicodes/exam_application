# Translates a question paper into Hindi with Claude, a few questions per request, filling only the
# questions that don't have a Hindi version yet. Needs ANTHROPIC_API_KEY on the server.
class HindiTranslator
  class Error < StandardError; end

  MODEL = :"claude-opus-5-5"
  BATCH = 15

  INSTRUCTIONS = <<~TEXT.freeze
    You translate multiple-choice questions for an Indian job aptitude test from English into Hindi.
    Write natural, clear Hindi in Devanagari, the way Indian competitive exams phrase questions, so a
    candidate who reads only Hindi understands each question exactly as the English one is meant.
    Keep unchanged: numbers, ₹ / % / units, names of people and places, codes and IDs (e.g. ASA/FCO/2026/1784),
    letter or word puzzles whose answer depends on the English letters (e.g. "If PROJECT is coded as QSPKFDU"),
    and abbreviations such as MIS. Keep every line break, and keep table rows written as "a | b | c" as rows
    with the same number of " | " cells (translate only the words inside the cells).
    Return the same number of options in the same order. Do not solve the questions or add anything.
  TEXT

  SCHEMA = {
    type: "object",
    properties: {
      questions: {
        type: "array",
        items: {
          type: "object",
          properties: {
            id: { type: "integer" },
            question: { type: "string" },
            options: { type: "array", items: { type: "string" } }
          },
          required: %w[id question options],
          additionalProperties: false
        }
      }
    },
    required: %w[questions],
    additionalProperties: false
  }.freeze

  def self.available?
    ENV["ANTHROPIC_API_KEY"].present?
  end

  def initialize(quiz)
    @quiz = quiz
  end

  # Returns the number of questions translated.
  def translate!
    client = Anthropic::Client.new
    todo = @quiz.questions.reject(&:hindi?)
    todo.each_slice(BATCH).sum do |batch|
      results = request(client, batch).index_by { |r| r["id"] }
      batch.count do |question|
        r = results[question.id]
        next false unless r && r["question"].present? && r["options"].size == question.options.size

        question.update!(body_hi: r["question"], options_hi: r["options"])
      end
    end
  end

  private
    def request(client, batch)
      payload = batch.map { |q| { id: q.id, question: q.body, options: q.options } }
      message = client.beta.messages.create(
        model: MODEL,
        max_tokens: 16_000,
        system_: INSTRUCTIONS,
        output_config: { effort: :low, format_: { type: :json_schema, schema: SCHEMA } },
        betas: [ "server-side-fallback-2026-07-01" ],
        fallbacks: :default, # if Claude declines, the API retries on its default fallback model
        messages: [ { role: "user", content: payload.to_json } ]
      )
      raise Error, "The translation was declined (#{message.stop_details&.category || 'policy'})" if message.stop_reason == :refusal
      raise Error, "The translation was cut off — try again" if message.stop_reason == :max_tokens

      text = message.content.select { |block| block.type == :text }.map(&:text).join
      JSON.parse(text).fetch("questions")
    rescue JSON::ParserError, KeyError
      raise Error, "The translation came back in an unexpected format — try again"
    rescue Anthropic::Errors::AuthenticationError
      raise Error, "The Anthropic API key is not valid"
    rescue Anthropic::Errors::RateLimitError
      raise Error, "The translation service is busy — try again in a minute"
    rescue Anthropic::Errors::APIConnectionError
      raise Error, "Could not reach the translation service"
    rescue Anthropic::Errors::APIStatusError => e
      raise Error, "Translation failed (#{e.status})"
    end
end
