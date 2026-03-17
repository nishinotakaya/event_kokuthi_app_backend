module Posting
  class ConnpassService < BaseService
    private

    def execute(page, content, ef)
      csrftoken = ensure_login(page)
      title     = extract_title(ef, content, 80)

      place = ef['place'].presence || 'オンライン'
      cap   = ef['capacity'].to_i.positive? ? ef['capacity'].to_i : 50

      default_ymd = default_date_plus(30)
      start_dt = fmt_dt(ef['startDate'], ef['startTime'])
      end_dt   = fmt_dt(ef['endDate'].presence || ef['startDate'], ef['endTime'])
      start_ms = (Date.parse(ef['startDate'].presence&.gsub('/', '-') || default_ymd)).to_time.to_i * 1000
      open_start = fmt_iso(start_ms - 7 * 24 * 60 * 60 * 1000)
      open_end   = fmt_iso(start_ms - 1 * 24 * 60 * 60 * 1000)

      # Create event
      log("[connpass] POST /api/event/ body: #{({ title: title }).to_json}")
      create_result = page.evaluate(<<~JS, arg: { title: title, csrftoken: csrftoken })
        async ({ title, csrftoken }) => {
          const res = await fetch('/api/event/', {
            method: 'POST',
            headers: { 'content-type': 'application/json', 'x-csrftoken': csrftoken, 'x-requested-with': 'XMLHttpRequest' },
            credentials: 'include',
            body: JSON.stringify({ title, allow_conflict_join: 'true', place: null }),
          });
          return { ok: res.ok, status: res.status, text: await res.text() };
        }
      JS

      raise "イベント作成失敗: #{create_result['status']} #{create_result['text']}" unless create_result['ok']
      created  = JSON.parse(create_result['text'])
      event_id = created['id']
      log("[connpass] ✅ イベント作成 ID: #{event_id}")

      # Build body
      lines      = content.split("\n")
      first_line = lines.first.to_s.gsub(/\A[#\s「『【]+/, '').gsub(/[】』」\s]+\z/, '').strip
      body       = (first_line.present? && title.include?(first_line)) ? lines.drop(1).join("\n").lstrip : content
      zoom_line  = ef['zoomUrl'].present? ? "\n\n■ Zoom URL\n#{ef['zoomUrl']}" : ''

      put_body = created.merge(
        'description_input' => body + zoom_line,
        'description'       => body + zoom_line,
        'status'            => 'draft',
        'place'             => nil,
        'start_datetime'    => start_dt,
        'end_datetime'      => end_dt,
        'open_start_datetime' => open_start,
        'open_end_datetime'   => open_end,
      )
      if put_body['participation_types'].is_a?(Array) && put_body['participation_types'].first
        put_body['participation_types'].first['max_participants'] = cap
      end

      log("[connpass] PUT /api/event/#{event_id} 更新中...")
      put_result = page.evaluate(<<~JS, arg: { eventId: event_id, csrftoken: csrftoken, body: put_body })
        async ({ eventId, csrftoken, body }) => {
          const res = await fetch(`/api/event/${eventId}`, {
            method: 'PUT',
            headers: { 'content-type': 'application/json', 'x-csrftoken': csrftoken,
                       'x-requested-with': 'XMLHttpRequest', 'referer': `https://connpass.com/event/${eventId}/edit/` },
            credentials: 'include',
            body: JSON.stringify(body),
          });
          return { ok: res.ok, status: res.status, text: await res.text() };
        }
      JS

      raise "本文更新失敗: #{put_result['status']} #{put_result['text']}" unless put_result['ok']
      updated = JSON.parse(put_result['text'])
      log("[connpass] ✅ 投稿完了 → #{updated['public_url']}")
    end

    def ensure_login(page)
      log("[connpass] ログイン確認中...")
      page.goto('https://connpass.com/editmanage/', waitUntil: 'domcontentloaded', timeout: 30_000)
      page.wait_for_timeout(1000)

      if page.url.include?('login') || page.url.include?('signin') || page.url.include?('sign_in')
        log("[connpass] ログイン中...")
        page.goto('https://connpass.com/login/', waitUntil: 'domcontentloaded', timeout: 30_000)
        page.fill('input[name="username"],input[name="email"]', ENV['CONPASS__KOKUCIZE_MAIL'].to_s) rescue \
          page.fill('input[name="email"]', ENV['CONPASS__KOKUCIZE_MAIL'].to_s)
        page.fill('input[name="password"]', ENV['CONPASS_KOKUCIZE_PASSWORD'].to_s)
        page.expect_navigation(timeout: 30_000) { page.click('form:has(input[name="username"]) button[type="submit"]') rescue page.click('button[type="submit"]') } rescue nil
        page.wait_for_load_state('networkidle', timeout: 20_000) rescue nil

        raise "connpass ログイン失敗" if page.url.include?('login') || page.url.include?('signin')
        log("[connpass] ✅ ログイン完了 → #{page.url}")
        page.goto('https://connpass.com/editmanage/', waitUntil: 'domcontentloaded', timeout: 30_000)
      else
        log("[connpass] ✅ ログイン済み")
      end

      result = page.evaluate(<<~JS)
        () => {
          const csrf = document.cookie.split(';').find(c => c.trim().startsWith('connpass-csrftoken='));
          return csrf ? csrf.split('=')[1].trim() : null;
        }
      JS
      raise "CSRFトークンが取得できませんでした" unless result
      log("[connpass] csrftoken: #{result[0, 8]}...")
      result
    end

    def fmt_dt(date, time)
      d = (date.to_s.gsub('/', '-').presence || default_date_plus(30))[0, 10]
      t = (time || '10:00').to_s.sub(/\A(\d):/, '0\1:') + ':00'
      "#{d}T#{t}"
    end

    def fmt_iso(ms)
      d = Time.at(ms / 1000).utc
      "#{d.strftime('%Y-%m-%d')}T00:00:00"
    end
  end
end
