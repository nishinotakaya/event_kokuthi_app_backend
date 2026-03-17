module Posting
  class TechplayService < BaseService
    LOGIN_URL  = 'https://techplay.jp/signin'
    MYPAGE_URL = 'https://techplay.jp/'
    CREATE_URL = -> { ENV.fetch('TECHPLAY_CREATE_URL', 'https://techplay.jp/event/create') }

    private

    def execute(page, content, ef)
      ensure_login(page)
      fill_and_submit(page, content, ef)
    end

    def ensure_login(page)
      log("[TechPlay] ログイン確認 → #{MYPAGE_URL}")
      page.goto(MYPAGE_URL, waitUntil: 'domcontentloaded', timeout: 30_000)
      page.wait_for_timeout(1000)

      return log("[TechPlay] ✅ ログイン済み") unless page.url.match?(/login|signin|sign_in/)

      log("[TechPlay] ログイン中 → #{LOGIN_URL}")
      page.goto(LOGIN_URL, waitUntil: 'domcontentloaded', timeout: 30_000)
      page.fill('input[name="email"]', ENV['TECHPLAY_EMAIL'].to_s)
      page.fill('input[name="password"]', ENV['TECHPLAY_PASSWORD'].to_s)
      page.expect_navigation(timeout: 30_000) { page.click('button[type="submit"]') } rescue nil
      page.wait_for_load_state('networkidle', timeout: 20_000) rescue nil

      raise "[TechPlay] ログインに失敗しました" if page.url.match?(/login|signin|sign_in/)
      log("[TechPlay] ✅ ログイン完了 → #{page.url}")
    end

    def fill_and_submit(page, content, ef)
      create_url = CREATE_URL.call
      log("[TechPlay] 投稿ページへ移動 → #{create_url}")
      page.goto(create_url, waitUntil: 'domcontentloaded', timeout: 30_000)
      page.wait_for_load_state('networkidle', timeout: 20_000) rescue nil

      url = page.url
      raise "[TechPlay] 投稿ページアクセス失敗" if url.match?(/login|signin/)
      raise "[TechPlay] ページが見つかりません (404)" if (page.title rescue '').include?('404')

      # Required fields
      fields = page.evaluate(<<~JS)
        [...document.querySelectorAll('input, textarea, select')].map(el => ({
          tag: el.tagName.toLowerCase(), type: el.type || '',
          name: el.name || '', id: el.id || '', ph: el.placeholder || '',
          required: el.required || el.getAttribute('aria-required') === 'true',
        }))
      JS

      default_date = (Date.today + 30).strftime('%Y-%m-%d')
      default_datetime = "#{default_date}T10:00"

      fields.select { |f| f['required'] }.each do |f|
        sel = f['id'].present? ? "##{f['id']}" : "#{f['tag']}[name=\"#{f['name']}\"]"
        el = page.locator(sel).first rescue next
        next unless el.visible?(timeout: 1000) rescue false
        next if (el.input_value rescue '').present?

        case f['tag']
        when 'select'
          page.evaluate("const el = document.querySelector('#{sel.gsub("'", "\\'")}'); const opt = el && [...el.options].find(o => o.value && o.value !== '0' && o.value !== ''); if (opt) el.value = opt.value;") rescue nil
        else
          case f['type']
          when 'datetime-local' then el.fill(default_datetime) rescue nil
          when 'date'           then el.fill(default_date) rescue nil
          when 'time'           then el.fill('10:00') rescue nil
          when 'number'         then el.fill('50') rescue nil
          when 'text', ''
            n = "#{f['name']}#{f['id']}#{f['ph']}".downcase
            val = if n.match?(/place|venue|会場|場所/) then 'オンライン'
                  elsif n.match?(/url|link/)           then 'https://example.com'
                  elsif n.match?(/email|mail/)         then ENV['TECHPLAY_EMAIL'].to_s
                  elsif n.match?(/tel|phone/)          then '000-0000-0000'
                  else '要確認'
                  end
            el.fill(val) rescue nil
          end
        end
      end

      # Fill content in textarea
      textarea_sels = fields.select { |f| f['tag'] == 'textarea' }
                           .map { |f| f['name'].present? ? "textarea[name=\"#{f['name']}\"]" : (f['id'].present? ? "##{f['id']}" : nil) }
                           .compact
      content_sel = find_first_visible(page, *textarea_sels, 'div[contenteditable="true"]', 'textarea')
      raise "[TechPlay] 本文フィールドが見つかりません" unless content_sel
      page.fill(content_sel, content)

      # Fill title
      title_sel = find_first_visible(page, 'input[name="title"]', '#title', 'input[name="name"]', '#name')
      if title_sel
        current = page.input_value(title_sel) rescue ''
        if current.blank?
          title_text = extract_title(ef, content, 80)
          page.fill(title_sel, title_text)
        end
      end

      # Submit
      submit_sel = find_first_visible(page,
        'button[type="submit"]', 'input[type="submit"]',
        'button:text("投稿")', 'button:text("保存")', 'button:text("公開")',
      )
      raise "[TechPlay] 送信ボタンが見つかりません" unless submit_sel
      log("[TechPlay] 送信: #{submit_sel}")
      page.expect_navigation(timeout: 30_000) { page.click(submit_sel) } rescue nil

      raise "[TechPlay] ページが見つかりません (404)" if (page.title rescue '').include?('404')
      log("[TechPlay] ✅ 投稿完了 → #{page.url}")
    end

    def find_first_visible(page, *selectors)
      selectors.each do |sel|
        visible = page.locator(sel).first.visible?(timeout: 1_000) rescue false
        return sel if visible
      end
      nil
    end
  end
end
