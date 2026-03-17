module Posting
  class PeatixService < BaseService
    GROUP_ID = -> {
      url = ENV.fetch('PEATIX_CREATE_URL', 'https://peatix.com/group/16510066/event/create')
      m = url.match(/group\/(\d+)/)
      m ? m[1] : '16510066'
    }

    private

    def execute(page, content, ef)
      bearer = login_and_get_bearer(page)
      title  = extract_title(ef, content, 100)
      group_id = GROUP_ID.call

      # Strip title line from body if it matches
      lines = content.split("\n")
      first_line = lines.first.to_s.gsub(/\A[#\s「『【]+/, '').gsub(/[】』」\s]+\z/, '').strip
      body_text = (first_line.present? && title.include?(first_line)) ? lines.drop(1).join("\n").lstrip : content
      zoom_line = ef['zoomUrl'].present? ? "\n\n■ Zoom URL\n#{ef['zoomUrl']}" : ''

      start_utc = to_utc(ef['startDate'], ef['startTime'])
      end_utc   = to_utc(ef['endDate'].presence || ef['startDate'], ef['endTime'].presence || ef['startTime'])

      # Step1: Create event
      create_body = {
        name: title, groupId: group_id, locationType: 'online',
        schedulingType: 'single', countryId: 392,
        start: { utc: start_utc, timezone: 'Asia/Tokyo' },
        end:   { utc: end_utc,   timezone: 'Asia/Tokyo' },
      }
      log("[Peatix] POST /v4/events: \"#{title}\"")

      create_result = page.evaluate(<<~JS, arg: { body: create_body, bearer: bearer, groupId: group_id })
        async ({ body, bearer, groupId }) => {
          const res = await fetch('https://peatix-api.com/v4/events', {
            method: 'POST',
            headers: { 'content-type': 'application/json', 'authorization': `Bearer ${bearer}`,
                       'origin': 'https://peatix.com', 'referer': `https://peatix.com/group/${groupId}/event/create`,
                       'x-requested-with': 'XMLHttpRequest' },
            body: JSON.stringify(body),
          });
          return { ok: res.ok, status: res.status, text: await res.text() };
        }
      JS

      raise "Peatix イベント作成失敗: #{create_result['status']} #{create_result['text']}" unless create_result['ok']

      created  = JSON.parse(create_result['text'])
      event_id = created['id'] || created['eventId']
      log("[Peatix] ✅ イベント作成 ID: #{event_id}")

      # Step2: Update description
      if event_id && body_text.present?
        log("[Peatix] PATCH /v4/events/#{event_id} 説明文更新中...")
        patch_result = page.evaluate(<<~JS, arg: { eventId: event_id, bearer: bearer, description: body_text + zoom_line })
          async ({ eventId, bearer, description }) => {
            const res = await fetch(`https://peatix-api.com/v4/events/${eventId}`, {
              method: 'PATCH',
              headers: { 'content-type': 'application/json', 'authorization': `Bearer ${bearer}`,
                         'origin': 'https://peatix.com', 'referer': `https://peatix.com/event/${eventId}/edit`,
                         'x-requested-with': 'XMLHttpRequest' },
              body: JSON.stringify({ details: { description } }),
            });
            return { ok: res.ok, status: res.status, text: await res.text() };
          }
        JS
        if patch_result['ok']
          log("[Peatix] ✅ 説明文更新完了")
        else
          log("[Peatix] ⚠️ 説明文更新失敗 (#{patch_result['status']})")
        end
      end

      event_url = created.dig('details', 'longUrl') || "https://peatix.com/event/#{event_id}"
      log("[Peatix] ✅ 投稿完了 → #{event_url}")
    end

    def login_and_get_bearer(page)
      log("[Peatix] ログイン中...")
      page.goto('https://peatix.com/signin', waitUntil: 'domcontentloaded', timeout: 30_000)

      unless page.url.include?('signin') || page.url.include?('login')
        log("[Peatix] ✅ ログイン済み → #{page.url}")
      else
        page.fill('input[name="username"]', ENV['PEATIX_EMAIL'].to_s)
        page.click('#next-button')
        page.wait_for_url('**/user/signin', timeout: 15_000) rescue nil
        page.wait_for_selector('input[type="password"]', timeout: 10_000) rescue nil
        page.fill('input[type="password"]', ENV['PEATIX_PASSWORD'].to_s)
        page.expect_navigation(timeout: 20_000) { page.click('#signin-button') } rescue nil

        after_url = page.url
        raise "Peatix ログイン失敗" if after_url.include?('signin') || after_url.include?('login')
        log("[Peatix] ✅ ログイン完了 → #{after_url}")
      end

      group_id   = GROUP_ID.call
      create_url = ENV.fetch('PEATIX_CREATE_URL', "https://peatix.com/group/#{group_id}/event/create")
      page.goto(create_url, waitUntil: 'domcontentloaded', timeout: 30_000)
      page.wait_for_timeout(5000)

      token = page.evaluate("localStorage.getItem('peatix_frontend_access_token')")
      raise "Bearer トークンが取得できませんでした" if token.nil? || token.empty?
      log("[Peatix] Bearer取得: #{token[0, 8]}...")
      token
    end

    def to_utc(date_str, time_str)
      d = date_str.to_s.gsub('/', '-').presence || default_date_plus(30)
      t = pad_time(time_str || '10:00')
      Time.parse("#{d}T#{t}:00+09:00").utc.strftime('%Y-%m-%dT%H:%M:%SZ')
    end
  end
end
