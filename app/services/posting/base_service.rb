module Posting
  class BaseService
    def call(page, content, event_fields = {}, &log_callback)
      @log_callback = log_callback
      execute(page, content, event_fields)
    end

    private

    def log(msg)
      @log_callback&.call(msg.to_s)
    end

    def extract_title(ef, content, max_len = 80)
      raw = ef['title'].presence ||
            ef['name'].presence ||
            content.split("\n").first.to_s.gsub(/\A[#【\s「『]+/, '').gsub(/[】』」\s]+\z/, '')
      raw.to_s[0, max_len].presence || 'イベント'
    end

    def pad_time(t)
      return '10:00' if t.blank?
      t.to_s.sub(/\A(\d):/, '0\1:')
    end

    def default_date_plus(days)
      (Date.today + days).strftime('%Y-%m-%d')
    end

    def normalize_date(d)
      d.to_s.gsub('/', '-')
    end
  end
end
