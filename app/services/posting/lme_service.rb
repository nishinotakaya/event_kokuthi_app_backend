module Posting
  class LmeService < BaseService
    ITEMS_DEFAULT_TAG = [
      { category_name: '未分類', id: 928568, name: '奥野代理店流入',  line_user: 0,  position: 428860, created_at: '2024.08.30', action_id: nil },
      { category_name: '未分類', id: 906833, name: 'フィリピン不動産', line_user: 10, position: 423227, created_at: '2024.08.17', action_id: nil },
      { category_name: '未分類', id: 450326, name: '体験会参加しない', line_user: 8,  position: 308479, created_at: '2023.11.25', action_id: nil },
      { category_name: '未分類', id: 450325, name: '体験会参加',      line_user: 10, position: 308478, created_at: '2023.11.25', action_id: nil },
    ].freeze

    TAIKEN_TAG_GROUP_ID      = '5238317'.freeze
    TAIKEN_TEMPLATE_GROUP_ID = '14088042'.freeze
    TAIKEN_TEMPLATE_CHILD_ID = '14088044'.freeze
    TAIKEN_MSG_TEMPLATE_ID   = '14088038'.freeze  # create-message-by-template で指定するパークグループ
    TAIKEN_PARK_TEMPLATE_ID  = '14088102'.freeze  # message-save で保存するパーク子テンプレート
    TAIKEN_PANEL_ID          = 1857170
    TAIKEN_TEMPLATE_ID       = 14088044
    TAIKEN_ACTION_ID_SANKA   = '20049679'.freeze
    TAIKEN_ACTION_ID_FUSANKA = '20049680'.freeze
    TAIKEN_BUTTON_SANKA_ID   = 2731205
    TAIKEN_BUTTON_FUSANKA_ID = 2731206
    TAIKEN_IMG_PATH          = '/ext-media-step/media/images/32480/17106/FcIyM873YXWDPEryJelR8LiviiUCaciKa8q9TqEW.png'.freeze

    private

    def execute(page, content, ef)
      base_url = (ENV['LME_BASE_URL'] || 'https://step.lme.jp').delete('"')
      bot_id   = ENV['LME_BOT_ID'] || '17106'

      # 1. Login
      login(page, base_url)

      # 2. Account selection
      account_type = ef['lmeAccount'].presence || 'taiken'
      active_page  = select_account(page, base_url, account_type)

      # 2b. 体験会の場合: テンプレート・タグを投稿前に更新
      new_tmpl_id = nil
      if account_type == 'taiken'
        log("[LME] 体験会テンプレート更新を開始します...")
        new_tmpl_id = setup_taiken_template(active_page, base_url, ef)
        log("[LME] ✅ 体験会テンプレート更新完了 tmpl_id=#{new_tmpl_id}")
      end

      # 3. Navigate to broadcast page for CSRF
      active_page.goto("#{base_url}/basic/message-send-all", waitUntil: 'domcontentloaded', timeout: 30_000)
      active_page.wait_for_load_state('networkidle', timeout: 15_000) rescue nil

      # 4. Profile
      log("[LME] プロファイル取得中...")
      profile_res = lme_fetch(active_page, base_url, '/ajax/broadcast/init-list-bots-profiles',
                              body: 'profile_id=', content_type: 'application/x-www-form-urlencoded; charset=UTF-8')
      profile = profile_res.dig('data', 0)
      raise "[LME] プロファイルが取得できませんでした: #{profile_res.to_json}" unless profile
      log("[LME] プロファイル: id=#{profile['id']} name=#{profile['nick_name']}")

      # 5. Active friends count
      log("[LME] アクティブ友達数取得中...")
      overview_res   = lme_fetch(active_page, base_url, '/basic/static-overview', method: 'GET')
      today_str      = Date.today.strftime('%Y-%m-%d')
      filter_number  = overview_res.dig('dates', today_str, 'active_friend') || 471
      log("[LME] アクティブ友達数: #{filter_number}")

      # 6. Broadcast name + schedule
      name      = extract_title(ef, content, 50).presence || 'イベントお知らせ'
      send_day  = ef['lmeSendDate'].presence || today_str
      send_time = ef['lmeSendTime'].presence || '10:00'
      log("[LME] 配信日時: #{send_day} #{send_time}")

      # 7. Create broadcast draft
      log("[LME] 下書き作成中... name=\"#{name}\"")
      broadcast_body = build_broadcast_params(name, send_day, send_time, profile, filter_number)
      broadcast_res  = lme_fetch(active_page, base_url, '/ajax/save-broadcast-v2',
                                 body: broadcast_body, content_type: 'application/x-www-form-urlencoded; charset=UTF-8')
      log("[LME] save-broadcast-v2: #{broadcast_res.to_json}")

      broadcast_id = broadcast_res['broadcastIdNew'] || broadcast_res['broadcast_id'] ||
                     broadcast_res.dig('data', 'id') || broadcast_res['id']
      raise "[LME] broadcast_id が取得できませんでした: #{broadcast_res.to_json}" unless broadcast_id
      log("[LME] broadcast_id=#{broadcast_id}")

      # 7b. Get detail then update send_day/send_time
      log("[LME] get-detail-broadcast-v2...")
      detail_res = lme_fetch(active_page, base_url, '/ajax/get-detail-broadcast-v2',
                             body: "broadcast_id=#{broadcast_id}", content_type: 'application/x-www-form-urlencoded; charset=UTF-8')
      detail = detail_res['data'] || detail_res
      update_body = build_broadcast_params(
        detail['name'] || name, send_day, send_time, profile,
        detail['filter_number'] || filter_number,
        broadcast_id: broadcast_id,
        type: detail['type'],
        filter_date: detail['filter_date'],
        action_id: detail['action_id'],
      )
      update_res = lme_fetch(active_page, base_url, '/ajax/save-broadcast-v2',
                             body: update_body, content_type: 'application/x-www-form-urlencoded; charset=UTF-8')
      log("[LME] 配信日時更新: #{update_res.to_json}")

      # 8. Save filter
      log("[LME] フィルター保存中（#{account_type == 'benkyokai' ? '勉強会' : '体験会'}）...")
      item_search = build_filter(account_type)
      filter_body = URI.encode_www_form(
        item_search: item_search.to_json,
        item_search_or: '[]',
        parent_id: broadcast_id.to_s,
        parent_type: 'broadcast',
        keyword: '',
        richMenuRedirectId: '0',
        richMenuItemId: '0',
      )
      filter_res = lme_fetch(active_page, base_url, '/ajax/filter/save-filter-v2',
                             body: filter_body, content_type: 'application/x-www-form-urlencoded; charset=UTF-8')
      log("[LME] save-filter-v2: #{filter_res.to_json}")

      # 9. メッセージ本文を保存（体験会・勉強会 共通）
      log("[LME] メッセージ本文を保存中...")
      template_json = {
        type: 'text',
        message_button: {}, message_media: {}, message_stamp: {}, message_location: {},
        message_text: { content: content, urls: [], number_action_url_redirect: 1, use_preview_url: 1, is_shorten_url: 1 },
        message_introduction: {},
        template_group_id: '-11', template_child_id: '', tmp_name: '',
        action_type: 'sendAll',
        broadcastId: broadcast_id.to_s,
        scheduleSendId: '', conversationId: '', content: '', address: '', latitude: '', longitude: '',
      }.to_json

      template_res = active_page.evaluate(<<~JS, arg: [base_url, broadcast_id.to_s, template_json])
        async ([base, broadcastId, templateJson]) => {
          const rawCookie = document.cookie.split(';').find(c => c.trim().startsWith('XSRF-TOKEN='));
          const csrfToken = rawCookie ? decodeURIComponent(rawCookie.split('=').slice(1).join('=')) : '';
          const fd = new FormData();
          fd.append('data', templateJson);
          fd.append('file_media', new Blob([]));
          fd.append('thumbnail_media', new Blob([]));
          fd.append('action_type', 'sendAll');
          fd.append('templateName', '');
          fd.append('folderId', '0');
          const res = await fetch(`${base}/ajax/template-v2/save-template`, {
            method: 'POST',
            headers: { 'X-CSRF-TOKEN': csrfToken, 'X-Requested-With': 'XMLHttpRequest',
                       'Referer': `${base}/basic/template-v2/add-template?template_group_id=-11&action_type=sendAll&broadcastId=${broadcastId}`,
                       'X-Server': 'data' },
            body: fd,
          });
          const text = await res.text();
          try { return JSON.parse(text); } catch { return { _text: text, _status: res.status }; }
        }
      JS
      log("[LME] save-template: #{template_res.to_json}")
      raise "[LME] テンプレート保存失敗: #{template_res.to_json}" if template_res['status'] == false || template_res['success'] == false

      # 9b. 体験会: ボタンパネルテンプレートもブロードキャストに追加
      if account_type == 'taiken'
        use_tmpl_id = new_tmpl_id || TAIKEN_MSG_TEMPLATE_ID
        log("[LME] 体験会ボタンパネルをブロードキャストに追加中 (template_id=#{use_tmpl_id})...")
        add_tmpl_res = lme_fetch(
          active_page, base_url, '/ajax/broadcast/create-message-by-template',
          body: URI.encode_www_form(template_id: use_tmpl_id, broadcast_id: broadcast_id.to_s),
          content_type: 'application/x-www-form-urlencoded; charset=UTF-8',
        )
        log("[LME] create-message-by-template: #{add_tmpl_res.to_json}")
      end

      log("[LME] ✅ 下書き作成完了 broadcast_id=#{broadcast_id} → #{base_url}/basic/add-broadcast-v2?broadcast_id=#{broadcast_id}")
    end

    def login(page, base_url)
      raise "[LME] LME_EMAIL / LME_PASSWORD が未設定" if ENV['LME_EMAIL'].blank? || ENV['LME_PASSWORD'].blank?

      log("[LME] トップページへ移動")
      page.goto("#{base_url}/", waitUntil: 'domcontentloaded', timeout: 30_000)
      page.wait_for_load_state('networkidle', timeout: 15_000) rescue nil

      title = page.title rescue ''
      url   = page.url
      log("[LME] title=\"#{title}\" url=#{url}")

      on_login_page = url.end_with?('/') || url.include?('/login') || url.include?('/signin') ||
                      title.include?('ログイン') || title.downcase.include?('login')
      has_session   = page.context.cookies.any? { |c| c[:name] == 'laravel_session' || c[:name] == 'XSRF-TOKEN' }

      if !on_login_page && has_session
        log("[LME] ✅ ログイン済み")
        return
      end

      email_sel = find_first(page, '#email_login', 'input[name="email"]')
      raise "[LME] メールフィールドが見つかりません" unless email_sel
      page.fill(email_sel, ENV['LME_EMAIL'].to_s)

      pass_sel = find_first(page, '#password_login', 'input[name="password"]')
      raise "[LME] パスワードフィールドが見つかりません" unless pass_sel
      page.fill(pass_sel, ENV['LME_PASSWORD'].to_s)

      # ===== reCAPTCHA (2captcha) =====
      # 複数セレクタで検出（LMEが .g-recaptcha を iframe 内に移している場合も考慮）
      captcha_sitekey = page.evaluate(<<~JS) rescue nil
        () => {
          // 1) data-sitekey 属性を持つ要素
          const el = document.querySelector('[data-sitekey]');
          if (el) return el.getAttribute('data-sitekey');
          // 2) g-recaptcha クラス
          const el2 = document.querySelector('.g-recaptcha');
          if (el2) return el2.getAttribute('data-sitekey') || '__found__';
          // 3) recaptcha iframe
          const iframe = document.querySelector('iframe[src*="recaptcha"], iframe[title*="reCAPTCHA"]');
          if (iframe) {
            const m = iframe.src.match(/[?&]k=([^&]+)/);
            return m ? m[1] : '__iframe__';
          }
          return null;
        }
      JS
      log("[LME] reCAPTCHA sitekey=#{captcha_sitekey.inspect}")

      if captcha_sitekey
        log("[LME] reCAPTCHA 検出 → 2captcha で解決中...")
        token = solve_recaptcha(page, page.url)
        page.evaluate(<<~JS, arg: token)
          (tok) => {
            let el = document.querySelector('#g-recaptcha-response');
            if (!el) {
              el = document.createElement('textarea');
              el.id   = 'g-recaptcha-response';
              el.name = 'g-recaptcha-response';
              el.style.display = 'none';
              document.body.appendChild(el);
            }
            el.value = tok;
            el.dispatchEvent(new Event('change', { bubbles: true }));
            // callback も呼ぶ
            if (typeof grecaptcha !== 'undefined') {
              try {
                const widgetId = Object.keys(grecaptcha).find(k => !isNaN(k));
                if (widgetId !== undefined) grecaptcha.getResponse(widgetId);
              } catch(e) {}
            }
          }
        JS
        log("[LME] ✅ reCAPTCHA 解決完了")
      else
        log("[LME] reCAPTCHA なし → スキップ")
      end

      log("[LME] ログインボタンをクリック")
      page.click('button[type="submit"]') rescue nil

      # URL が変わるまで最大 40 秒待機（SPA ルート変化にも対応）
      40.times do
        break unless page.url.end_with?('/')
        sleep 1
      end
      page.wait_for_load_state('networkidle', timeout: 15_000) rescue nil

      after_url   = page.url
      after_title = page.title rescue ''

      # ページ上のエラーメッセージを取得してログに出す
      err_msg = page.evaluate(<<~JS) rescue ''
        () => {
          const el = document.querySelector('.alert, .error, [class*="error"], [class*="alert"], .message-error, .form-error');
          return el ? el.innerText.trim() : '';
        }
      JS
      log("[LME] ログイン後 url=#{after_url} title=\"#{after_title}\"#{err_msg.present? ? " error=\"#{err_msg}\"" : ''}")

      if after_url.end_with?('/') || after_url.include?('/login') || after_title.include?('ログイン')
        detail = err_msg.present? ? " ページエラー:「#{err_msg}」" : ' (reCAPTCHAが検出できなかったか認証情報を確認)'
        raise "[LME] ログイン失敗 url=#{after_url}#{detail}"
      end

      log("[LME] ✅ ログイン完了 → #{after_url}")

      ts     = Time.now.to_i * 1000
      bot_id = ENV['LME_BOT_ID'] || '17106'
      page.goto("#{base_url}/basic/friendlist?botIdCurrent=#{bot_id}&isOtherBot=1&_ts=#{ts}", waitUntil: 'domcontentloaded', timeout: 30_000)
      page.wait_for_load_state('networkidle', timeout: 15_000) rescue nil

      unless page.url.include?('/basic/')
        page.goto("#{base_url}/basic/overview?botIdCurrent=#{bot_id}&isOtherBot=1&_ts=#{ts}", waitUntil: 'domcontentloaded', timeout: 30_000) rescue nil
      end
      log("[LME] ✅ セッション確定 → #{page.url}")
    end

    def solve_recaptcha(page, page_url)
      captcha_key = ENV['API2CAPTCHA_KEY']
      raise "[LME] API2CAPTCHA_KEY が未設定" if captcha_key.blank?

      sitekey = page.locator('.g-recaptcha').first.get_attribute('data-sitekey')

      uri = URI('http://2captcha.com/in.php')
      req = Net::HTTP::Post.new(uri)
      req['Content-Type'] = 'application/x-www-form-urlencoded'
      req.body = URI.encode_www_form(
        key: captcha_key, method: 'userrecaptcha',
        googlekey: sitekey, pageurl: page_url, json: '1',
      )
      res     = Net::HTTP.start(uri.host, uri.port) { |h| h.request(req) }
      in_json = JSON.parse(res.body)
      raise "[LME] 2captcha 投稿失敗: #{in_json.to_json}" unless in_json['status'] == 1

      request_id = in_json['request']
      sleep 20

      24.times do
        res_uri  = URI("http://2captcha.com/res.php?key=#{captcha_key}&action=get&id=#{request_id}&json=1")
        res_json = JSON.parse(Net::HTTP.get_response(res_uri).body)
        return res_json['request'] if res_json['status'] == 1
        raise "[LME] 2captcha エラー: #{res_json.to_json}" if res_json['request'] != 'CAPCHA_NOT_READY'
        sleep 5
      end
      raise "[LME] 2captcha タイムアウト（2分）"
    end

    def select_account(page, base_url, account_type)
      keyword = account_type == 'benkyokai' ? '勉強会' : '体験会'
      log("[LME] アカウント選択（プロアカ#{keyword}）")
      page.goto("#{base_url}/admin/home", waitUntil: 'domcontentloaded', timeout: 30_000)
      sleep 2

      context       = page.context
      new_page_prom = context.async_expect_event('page', timeout: 8000) rescue nil

      specific_els = page.query_selector_all("xpath=//*[contains(normalize-space(text()), 'プロアカ') and contains(normalize-space(text()), '#{keyword}')]") rescue []
      if specific_els.any?
        specific_els.first.click rescue nil
      else
        fallback = page.query_selector_all("xpath=//*[contains(normalize-space(text()), 'プロアカ')]") rescue []
        fallback.first.click rescue nil if fallback.any?
      end

      new_page = new_page_prom&.value rescue nil
      if new_page
        log("[LME] 新タブが開かれました → 切り替え")
        new_page.wait_for_load_state('domcontentloaded', timeout: 30_000) rescue nil
        new_page.wait_for_load_state('networkidle', timeout: 15_000) rescue nil
        log("[LME] アカウント選択完了 → #{new_page.url}")
        return new_page
      end

      sleep 2
      page.wait_for_load_state('networkidle', timeout: 15_000) rescue nil
      log("[LME] アカウント選択完了 → #{page.url}")
      page
    end

    def lme_fetch(page, base_url, path, method: 'POST', body: nil, content_type: nil)
      page.evaluate(<<~JS, arg: [base_url, path, method, body, content_type])
        async ([base, path, method, body, contentType]) => {
          const rawCookie = document.cookie.split(';').find(c => c.trim().startsWith('XSRF-TOKEN='));
          const csrfToken = rawCookie ? decodeURIComponent(rawCookie.split('=').slice(1).join('=')) : '';
          const headers = { 'X-CSRF-TOKEN': csrfToken, 'X-Requested-With': 'XMLHttpRequest' };
          if (contentType) headers['Content-Type'] = contentType;
          const res = await fetch(base + path, { method, headers, body });
          const text = await res.text();
          try { return JSON.parse(text); } catch { return { _text: text, _status: res.status }; }
        }
      JS
    end

    def find_first(page, *selectors)
      selectors.each do |sel|
        visible = page.locator(sel).first.visible?(timeout: 2_000) rescue false
        return sel if visible
      end
      nil
    end

    def build_broadcast_params(name, send_day, send_time, profile, filter_number,
                               broadcast_id: '', type: '', filter_date: '', action_id: '')
      URI.encode_www_form(
        broadcast_id: broadcast_id.to_s,
        type: type.to_s,
        send_day: send_day,
        send_time: send_time,
        setting_send_message: '1',
        profile_id: profile['id'].to_s,
        filter_number: filter_number.to_s,
        filter_date: filter_date.to_s,
        name: name,
        action_id: action_id.to_s,
        'profile_bot[id]'         => profile['id'].to_s,
        'profile_bot[bot_id]'     => profile['bot_id'].to_s,
        'profile_bot[user_id]'    => profile['user_id'].to_s,
        'profile_bot[avt_path]'   => profile['avt_path'].to_s,
        'profile_bot[nick_name]'  => profile['nick_name'].to_s,
        'profile_bot[is_default]' => profile['is_default'].to_s,
        'profile_bot[created_at]' => profile['created_at'].to_s,
        'profile_bot[updated_at]' => profile['updated_at'].to_s,
        'profile_bot[position]'   => profile['position'].to_s,
        checkFilter: '1',
        flag_setting_filter: '0',
        count_filter: filter_number.to_s,
        status: 'draft',
      )
    end

    # =====================================================================
    # 体験会テンプレート更新
    # 投稿前に: save-group → タグ作成 → アクション保存 → ボタンテンプレート保存
    # =====================================================================
    # 戻り値: create-message-by-template で使う template_id (String)
    def setup_taiken_template(active_page, base_url, ef)
      # タグ名: 今日ではなくイベント開催日を使う
      event_date_str = ef['eventDate'].presence || ef['startDate'].presence || ef['lmeSendDate'].presence
      event_date     = event_date_str ? (Date.parse(event_date_str) rescue Date.today) : Date.today
      tag_name       = "#{event_date.month}月#{event_date.day}日 参加予定"

      event_title   = ef['title'].presence || ef['name'].presence || '体験会'
      zoom_url      = ef['zoomUrl'].presence || ef['lmeZoomUrl'].presence || ''
      zoom_id       = ef['zoomId'].presence   || ef['lmeMeetingId'].presence || ''
      zoom_passcode = ef['zoomPasscode'].presence || ef['lmePasscode'].presence || ''

      # 0. テンプレートグループを新規作成 (save-group)
      # template_name にイベントタイトルを使う
      log("[LME][体験会テンプレ] テンプレートグループ作成中 (save-group) title=#{event_title}...")
      active_page.goto("#{base_url}/basic/message-template", waitUntil: 'domcontentloaded', timeout: 30_000)
      active_page.wait_for_load_state('networkidle', timeout: 15_000) rescue nil

      save_group_res = active_page.evaluate(<<~JS, arg: [base_url, event_title])
        async ([base, templateName]) => {
          const rawCookie = document.cookie.split(';').find(c => c.trim().startsWith('XSRF-TOKEN='));
          const csrfToken = rawCookie ? decodeURIComponent(rawCookie.split('=').slice(1).join('=')) : '';
          const fd = new FormData();
          fd.append('template_name', templateName);
          fd.append('folder_id', '5326677');
          fd.append('content', '');
          const res = await fetch(`${base}/ajax/template-v2/save-group`, {
            method: 'POST',
            headers: {
              'X-CSRF-TOKEN': csrfToken,
              'X-Requested-With': 'XMLHttpRequest',
              'Referer': `${base}/basic/message-template`,
            },
            body: fd,
          });
          const text = await res.text();
          try { return JSON.parse(text); } catch { return { _text: text, _status: res.status }; }
        }
      JS
      log("[LME][体験会テンプレ] save-group: #{save_group_res.to_json}")

      # 返ってきた template_group_id を取得（フォールバック: 既存の定数）
      # save-group は {"success":true,"redirect_url":"...?template_id=14096291"} 形式で返す
      new_group_id = extract_id_from_response(save_group_res)&.to_s
      if new_group_id.nil? && save_group_res.is_a?(Hash)
        redirect_url = save_group_res['redirect_url'].to_s
        m = redirect_url.match(/[?&]template_id=(\d+)/)
        new_group_id = m[1] if m
      end
      log("[LME][体験会テンプレ] new_group_id=#{new_group_id.inspect} (fallback=#{TAIKEN_TEMPLATE_GROUP_ID})")
      group_id  = new_group_id || TAIKEN_TEMPLATE_GROUP_ID
      child_id  = new_group_id ? '' : TAIKEN_TEMPLATE_CHILD_ID

      # 1. テンプレートページへ移動 + レスポンス傍受でタグリストを捕捉
      log("[LME][体験会テンプレ] テンプレートページへ移動（タグ一覧を傍受）...")
      intercepted_tag_responses = []
      intercept_handler = lambda do |response|
        if response.url.to_s.include?('get-list-group-tag')
          body = response.body rescue nil
          if body&.length.to_i > 0
            parsed = JSON.parse(body) rescue nil
            intercepted_tag_responses << parsed if parsed.is_a?(Hash)
            log("[LME][体験会テンプレ] 傍受: #{body[0, 300]}")
          end
        end
      rescue
        nil
      end
      active_page.on('response', intercept_handler)

      begin
        active_page.goto(
          "#{base_url}/basic/template-v2/add-template?template_group_id=#{group_id}&template_child_id=#{child_id}",
          waitUntil: 'domcontentloaded', timeout: 30_000,
        )
        active_page.wait_for_load_state('networkidle', timeout: 20_000) rescue nil
      ensure
        active_page.remove_listener('response', intercept_handler) rescue nil
      end

      # 2. タグリスト確定（傍受 → folder_id直叩き → group_id直叩き の順に試みる）
      tag_items = find_tag_items_from_responses(active_page, base_url, intercepted_tag_responses, tag_name: tag_name)
      log("[LME][体験会テンプレ] タグ数: #{tag_items.length} names=#{tag_items.map { |t| t['name'] }.first(5).inspect}")

      # 3. 今日の日付タグを取得 or 作成
      existing = tag_items.find { |t| t['name'] == tag_name }

      new_tag_id = if existing
        log("[LME][体験会テンプレ] 既存タグ使用: id=#{existing['id']} name=#{tag_name}")
        existing['id']
      else
        log("[LME][体験会テンプレ] タグ作成中: #{tag_name}")
        add_tag_res = lme_fetch(
          active_page, base_url, '/ajax/save-add-tag-in-modal-action',
          body: URI.encode_www_form(folder_id: TAIKEN_TAG_GROUP_ID, tag_name: tag_name),
          content_type: 'application/x-www-form-urlencoded; charset=UTF-8',
        )
        log("[LME][体験会テンプレ] タグ作成レスポンス: #{add_tag_res.to_json}")

        tid = extract_id_from_response(add_tag_res)

        if tid.nil?
          log("[LME][体験会テンプレ] IDなし（フルレスポンス=#{add_tag_res.to_json}）→ タグリスト再取得で名前検索...")
          retry_items = find_tag_items_from_responses(active_page, base_url, [], tag_name: tag_name)
          found = retry_items.find { |t| t['name'] == tag_name }
          log("[LME][体験会テンプレ] 再取得: #{retry_items.length}件 / found=#{found ? "yes id=#{found['id']}" : 'no'}")
          tid = found['id'] if found
        end
        tid
      end
      raise "[LME][体験会テンプレ] タグIDが取得できませんでした: tag_name=#{tag_name}" unless new_tag_id

      log("[LME][体験会テンプレ] タグID: #{new_tag_id} name=#{tag_name}")
      new_tag = build_new_tag(new_tag_id, tag_name, event_date)

      # 4. アクション保存（既存アクション id=TAIKEN_ACTION_ID_SANKA を UPDATE）
      # ブラウザキャプチャの構造: タグ(active:false) → テキスト/ZoomURL(active:true)
      log("[LME][体験会テンプレ] アクション保存中 (id=#{TAIKEN_ACTION_ID_SANKA} UPDATE)...")
      zoom_lines_for_action = ["以下のzoom URLで開催します！", "時間の5分前になりましたら入室してください👍", zoom_url]
      zoom_lines_for_action << "ミーティングID: #{zoom_id}" if zoom_id.present?
      zoom_lines_for_action << "パスコード: #{zoom_passcode}" if zoom_passcode.present?
      zoom_message_for_action = zoom_lines_for_action.join("\n")
      zoom_url_detect = zoom_url.present? ? [{ metadata: nil, url: zoom_url }] : []

      action_detail = [
        {
          type: 'tag', active: false, is_edit_content: false, change_filter: 0,
          group_open_template: 0, selected_group_id: 0, group_open_tag: 0,
          data: { ids: [new_tag_id.to_s], action: 1, is_select_all: false, filters: { and: [], or: [] } },
          list_tags: [new_tag],
          items_default_tag: ITEMS_DEFAULT_TAG.map { |t| t.transform_keys(&:to_s) },
          tag_items: tag_items,
        },
        {
          title: 'テキスト', type: 'text', active: true, is_edit_content: true, change_filter: 1,
          data: { content: zoom_message_for_action, filters: { and: [], or: [] } },
          urlDetect: zoom_url_detect,
        },
      ]
      action_res = lme_fetch(
        active_page, base_url, '/ajax/action/save',
        body: URI.encode_www_form(action_detail: action_detail.to_json, type: 'button_v2', id: TAIKEN_ACTION_ID_SANKA),
        content_type: 'application/x-www-form-urlencoded; charset=UTF-8',
      )
      log("[LME][体験会テンプレ] アクション保存: #{action_res.to_json}")

      # 5. ボタンテンプレート保存（ZoomURL・ID・パスコード・タグ動的注入）
      log("[LME][体験会テンプレ] テンプレート保存中 (group_id=#{group_id} ZoomURL=#{zoom_url.empty? ? '未設定' : '設定済み'})...")
      template_data = build_taiken_template_data(new_tag_id, new_tag, zoom_url, zoom_id, zoom_passcode,
                                                 template_group_id: group_id, template_child_id: child_id,
                                                 event_title: event_title)

      template_res = active_page.evaluate(<<~JS, arg: [base_url, template_data.to_json, group_id, child_id])
        async ([base, templateJson, groupId, childId]) => {
          const rawCookie = document.cookie.split(';').find(c => c.trim().startsWith('XSRF-TOKEN='));
          const csrfToken = rawCookie ? decodeURIComponent(rawCookie.split('=').slice(1).join('=')) : '';
          const fd = new FormData();
          fd.append('data', templateJson);
          fd.append('file_media', new Blob([]));
          fd.append('thumbnail_media', new Blob([]));
          fd.append('action_type', 'template');
          fd.append('templateName', '');
          fd.append('folderId', '0');
          const referer = childId
            ? `${base}/basic/template-v2/add-template?template_group_id=${groupId}&template_child_id=${childId}`
            : `${base}/basic/template-v2/add-template?template_group_id=${groupId}`;
          const res = await fetch(`${base}/ajax/template-v2/save-template`, {
            method: 'POST',
            headers: {
              'X-CSRF-TOKEN': csrfToken,
              'X-Requested-With': 'XMLHttpRequest',
              'Referer': referer,
              'X-Server': 'data',
            },
            body: fd,
          });
          const text = await res.text();
          try { return JSON.parse(text); } catch { return { _text: text, _status: res.status }; }
        }
      JS
      log("[LME][体験会テンプレ] テンプレート保存: #{template_res.to_json}")
      raise "[LME][体験会テンプレ] テンプレート保存失敗: #{template_res.to_json}" if template_res['status'] == false || template_res['success'] == false

      # 6. テンプレート保存後: park-template/list-template でサーバー状態を確定
      log("[LME][体験会テンプレ] park-template リスト確定中 (group_id=#{group_id})...")
      lme_fetch(active_page, base_url, "/basic/park-template/list-template/#{group_id}", method: 'GET')
      log("[LME][体験会テンプレ] park-template リスト確定完了")

      # create-message-by-template で使う template_id を返す
      group_id
    end

    # タグ一覧を確定させる（傍受レスポンス → folder_id直叩き → group_id直叩き の順）
    # グループ判定: count フィールドを持つ → グループ（除外）
    # タグ判定: count を持たず id と name を持つ → 個別タグ
    def find_tag_items_from_responses(active_page, base_url, intercepted, tag_name: nil)
      # 傍受データから個別タグ配列を探す
      intercepted.each do |res|
        items = extract_tag_array(res)
        return items if items.any?
      end

      # 直叩きパターン（ブラウザ実測値を最優先）
      # lme_api_taikennkai_seminay.md のブラウザキャプチャより: group_id=5238317&action=showGroup が正解
      bodies = [
        # ★ブラウザ実測値（最優先）
        "group_id=#{TAIKEN_TAG_GROUP_ID}&action=showGroup",
        # group_id 単体
        "group_id=#{TAIKEN_TAG_GROUP_ID}",
        "group_id=#{TAIKEN_TAG_GROUP_ID}&per_page=100",
        # group_open でグループを展開
        "folder_id=#{TAIKEN_TAG_GROUP_ID}&group_open=#{TAIKEN_TAG_GROUP_ID}&per_page=100",
        "folder_id=#{TAIKEN_TAG_GROUP_ID}&group_open=#{TAIKEN_TAG_GROUP_ID}",
        "group_id=#{TAIKEN_TAG_GROUP_ID}&group_open=#{TAIKEN_TAG_GROUP_ID}&per_page=100",
        # folder_id のみ
        "folder_id=#{TAIKEN_TAG_GROUP_ID}&per_page=100",
        "folder_id=#{TAIKEN_TAG_GROUP_ID}",
      ]
      if tag_name
        bodies.unshift("group_id=#{TAIKEN_TAG_GROUP_ID}&action=showGroup&keyword=#{CGI.escape(tag_name)}")
        bodies.unshift("group_id=#{TAIKEN_TAG_GROUP_ID}&keyword=#{CGI.escape(tag_name)}")
        bodies.unshift("folder_id=#{TAIKEN_TAG_GROUP_ID}&keyword=#{CGI.escape(tag_name)}")
      end

      bodies.each do |body|
        res = lme_fetch(active_page, base_url, '/ajax/get-list-group-tag',
                        body: body, content_type: 'application/x-www-form-urlencoded; charset=UTF-8')
        # フルレスポンスをログ（最初の1件のキー構造を把握するため）
        all_items = all_arrays_from_response(res)
        log("[LME][体験会テンプレ] get-list-group-tag(#{body.split('&').first}): " \
            "keys=#{res.is_a?(Hash) ? res.keys.inspect : res.class} " \
            "arrays=#{all_items.map { |k, v| "#{k}:#{v.length}件 first_keys=#{v.first&.keys&.first(5).inspect}" }.join(' | ')}")
        items = extract_tag_array(res)
        if items.any?
          log("[LME][体験会テンプレ] タグ取得成功(#{body.split('=').first}): #{items.length}件 names=#{items.map { |t| t['name'] }.first(5).inspect}")
          return items
        end

        # tag_items が空で groups (subgroup) が返ってきた場合 → 各 subgroup を再帰検索
        # action=showGroup のレスポンスにのみ subgroups が含まれる
        next unless body.include?('action=showGroup')
        subgroups = res.is_a?(Hash) ? Array(res['groups']).select { |g|
          g.is_a?(Hash) && g['id'] && g['id'].to_i != TAIKEN_TAG_GROUP_ID.to_i
        } : []
        next unless subgroups.any?
        log("[LME][体験会テンプレ] subgroups=#{subgroups.length}件 → 各 subgroup を検索中...")
        subgroups.each do |sg|
          sg_id = sg['id'].to_s
          sg_body = tag_name ? "group_id=#{sg_id}&action=showGroup&keyword=#{CGI.escape(tag_name)}" \
                             : "group_id=#{sg_id}&action=showGroup"
          sg_res = lme_fetch(active_page, base_url, '/ajax/get-list-group-tag',
                             body: sg_body, content_type: 'application/x-www-form-urlencoded; charset=UTF-8')
          sg_all = all_arrays_from_response(sg_res)
          log("[LME][体験会テンプレ] subgroup #{sg['name']}(#{sg_id}): " \
              "arrays=#{sg_all.map { |k, v| "#{k}:#{v.length}件" }.join(' | ')}")
          sg_items = extract_tag_array(sg_res)
          if sg_items.any?
            log("[LME][体験会テンプレ] subgroup #{sg['name']} でタグ発見: #{sg_items.length}件 names=#{sg_items.map { |t| t['name'] }.first(5).inspect}")
            return sg_items
          end
        end
      end

      []
    end

    # レスポンスからタグIDを広く探す
    def extract_id_from_response(res)
      return nil unless res.is_a?(Hash)
      # 直接 id
      return res['id'] if res['id'].is_a?(Integer)
      return res['tag_id'] if res['tag_id'].is_a?(Integer)
      # data キー配下
      if res['data'].is_a?(Hash)
        d = res['data']
        return d['id'] if d['id'].is_a?(Integer)
        return d['tag_id'] if d['tag_id'].is_a?(Integer)
        return d['tag']&.dig('id') if d['tag'].is_a?(Hash)
      end
      if res['data'].is_a?(Array) && res['data'].first.is_a?(Hash)
        return res['data'].first['id']
      end
      # tag キー配下
      if res['tag'].is_a?(Hash)
        return res['tag']['id']
      end
      # 任意の int id を持つネストされたオブジェクト
      res.each do |_k, v|
        next unless v.is_a?(Hash)
        return v['id'] if v['id'].is_a?(Integer)
      end
      nil
    end

    # レスポンス内の全配列を返す（デバッグ用）
    def all_arrays_from_response(res)
      return [] unless res.is_a?(Hash)
      result = {}
      res.each do |k, v|
        result[k] = v if v.is_a?(Array) && v.any?
        if v.is_a?(Hash)
          v.each do |k2, v2|
            result["#{k}.#{k2}"] = v2 if v2.is_a?(Array) && v2.any?
          end
        end
      end
      result
    end

    # レスポンス構造に依らずタグ配列を抽出
    # タグ判定: id と name を持ち、count フィールドを持たない（グループは count を持つ）
    # ※ items_default / tag_sort は「デフォルト表示用タグ」なので対象外
    def extract_tag_array(res)
      return [] unless res.is_a?(Hash)

      is_tag = lambda do |item|
        item.is_a?(Hash) && item['id'] && item['name'] && !item.key?('count')
      end

      # 明示的ホワイトリスト: tag_items が最優先（group が開いた時に個別タグが入るキー）
      # items_default / tag_sort は常に存在するデフォルトタグなので除外
      %w[tag_items tags items list data].each do |key|
        v = res[key]
        next unless v.is_a?(Array) && v.any?
        tags = v.select { |item| is_tag.call(item) }
        return tags if tags.any?
      end
      if res['data'].is_a?(Hash)
        %w[tag_items tags items list].each do |key|
          v = res['data'][key]
          next unless v.is_a?(Array) && v.any?
          tags = v.select { |item| is_tag.call(item) }
          return tags if tags.any?
        end
      end
      # 混合配列対応（groups 配列にタグが混在するケース）
      # ただし items_default / tag_sort / groups は意図的に除外
      # sort / tag_sort / items_default は全てデフォルト表示用の同一4件タグ → 除外
      excluded_keys = %w[items_default tag_sort sort groups]
      res.each do |key, v|
        next if excluded_keys.include?(key)
        next unless v.is_a?(Array) && v.any? && v.first.is_a?(Hash)
        tags = v.select { |item| is_tag.call(item) }
        return tags if tags.any?
      end
      []
    end

    def build_new_tag(new_tag_id, tag_name, today)
      {
        id: new_tag_id,
        bot_id: 17106,
        name: tag_name,
        category_id: TAIKEN_TAG_GROUP_ID.to_i,
        rich_menu_id: nil,
        position: 738391,
        add_template_id: nil,
        scenario_id: nil,
        scenario_day: nil,
        scenario_time: nil,
        is_2th_apply: 0,
        max_users_number: nil,
        ins_add_template_id: nil,
        ins_scenario_id: nil,
        ins_scenario_day: nil,
        ins_scenario_time: nil,
        ins_is_2th_apply: nil,
        ins_tag_id: nil,
        action_mode: 0,
        action_id: nil,
        created_at: today.strftime('%Y-%m-%d 00:00:00'),
        updated_at: nil,
        count_user_tag: 0,
        is_limit: 0,
        limit: 0,
        limit_action_id: nil,
        limit_action_mode: 0,
        deleted_at: nil,
        user_id_del: nil,
        setting_actions: [],
      }
    end

    def build_taiken_template_data(new_tag_id, new_tag, zoom_url, zoom_id = '', zoom_passcode = '',
                                   template_group_id: TAIKEN_TEMPLATE_GROUP_ID,
                                   template_child_id: TAIKEN_TEMPLATE_CHILD_ID,
                                   event_title: 'オンライン体験会')
      today_str    = Date.today.strftime('%Y-%m-%d')
      zoom_lines   = ["以下のzoom URLで開催します！", "時間の5分前になりましたら入室してください👍", zoom_url]
      zoom_lines << "ミーティングID: #{zoom_id}" if zoom_id.present?
      zoom_lines << "パスコード: #{zoom_passcode}" if zoom_passcode.present?
      zoom_message   = zoom_lines.join("\n")
      zoom_url_list  = zoom_url.present? ? [{ metadata: nil, url: zoom_url }] : []

      {
        type: 'form',
        message_button: {
          name: nil,
          type_button: 1,
          image_server: '',
          carousel_action_type: 0,
          content: '',
          type_size: nil,
          message_sent_when_exceed_click: '',
          is_send_message_when_exceed_click: 1,
          action_id_when_exceed_click: 0,
          flag_type_content_quick_reply: nil,
          thumbnail_path: '',
          list_panel: [
            {
              id: TAIKEN_PANEL_ID,
              template_id: TAIKEN_TEMPLATE_ID,
              title: event_title,
              text: '参加か不参加かをご選択ください',
              img_path: TAIKEN_IMG_PATH,
              created_at: "#{today_str} 00:00:00",
              updated_at: "#{today_str} 00:00:00",
              order: 1,
              image_server: 'https://p.lmes.jp',
              title_color: '#000000',
              title_background: '',
              text_color: '#000000',
              text_background: '',
              is_title_bold: 0,
              is_text_bold: 1,
              number_row_display: 1,
              default_label_color: '#FFFFFF',
              default_label_bg: '#08BF5A',
              is_apply_title: 1,
              is_apply_text: 1,
              width: 1408,
              height: 768,
              buttons: [
                {
                  id: TAIKEN_BUTTON_SANKA_ID,
                  button_id: TAIKEN_PANEL_ID,
                  button_number: 1,
                  post_back: 0,
                  method: 0,
                  label: '参加する',
                  data: nil,
                  scenario: 0,
                  tag: 0,
                  event_time_id: 0,
                  action_id: TAIKEN_ACTION_ID_SANKA,
                  type_open_url: 1,
                  order: 1,
                  form_id: nil,
                  booking_id: nil,
                  conversion_id: nil,
                  items_id: nil,
                  bill_type: 1,
                  site_script_id: 0,
                  label_color: '',
                  label_bg: '',
                  type_url_schema: 0,
                  data_url_schema: '',
                  flag_open_url_in_browser: 0,
                  is_setting_url_expired_date: 0,
                  date_url_expired_date: today_str,
                  time_url_expired_date: '23:59',
                  number_day_url_expired_date: nil,
                  calendar_id: nil,
                  url_expired: nil,
                  url_expired_message: nil,
                  calendar_salon_id: nil,
                  calendar_lesson_id: nil,
                  detail_action: [
                    {
                      type: 'tag',
                      data: { ids: [new_tag_id.to_s], action: 1, is_select_all: false, filters: { and: [], or: [] } },
                      active: false,
                      group_open_template: 0,
                      is_edit_content: false,
                      selected_group_id: 0,
                      list_tags: [new_tag],
                      group_open_tag: 0,
                      items_default_tag: ITEMS_DEFAULT_TAG.map { |t| t.transform_keys(&:to_s) },
                      change_filter: 0,
                      tag_items: [],
                    },
                    {
                      title: 'テキスト',
                      type: 'text',
                      data: { content: zoom_message, filters: { and: [], or: [] } },
                      active: true,
                      is_edit_content: true,
                      change_filter: 1,
                      urlDetect: zoom_url_list,
                    },
                  ],
                  flag_setting_action: 1,
                  flag_setting_action_default: 1,
                  flag_setting_expired_date: 1,
                  flag_action_url_expired: 2,
                },
                {
                  id: TAIKEN_BUTTON_FUSANKA_ID,
                  button_id: TAIKEN_PANEL_ID,
                  button_number: 1,
                  post_back: 0,
                  method: 0,
                  label: '参加しない',
                  data: nil,
                  scenario: 0,
                  tag: 0,
                  event_time_id: 0,
                  action_id: TAIKEN_ACTION_ID_FUSANKA,
                  type_open_url: 1,
                  order: 2,
                  form_id: nil,
                  booking_id: nil,
                  conversion_id: nil,
                  items_id: nil,
                  bill_type: 1,
                  site_script_id: 0,
                  label_color: '',
                  label_bg: '',
                  type_url_schema: 0,
                  data_url_schema: '',
                  flag_open_url_in_browser: 0,
                  is_setting_url_expired_date: 0,
                  date_url_expired_date: today_str,
                  time_url_expired_date: '23:59',
                  number_day_url_expired_date: nil,
                  calendar_id: nil,
                  url_expired: nil,
                  url_expired_message: nil,
                  calendar_salon_id: nil,
                  calendar_lesson_id: nil,
                  detail_action: [
                    {
                      type: 'text',
                      data: { content: "月二回開催しています！！\n次回のタイミングでご参加お待ちしております✨" },
                      active: true,
                      group_open_template: 0,
                      is_edit_content: false,
                      selected_group_id: 0,
                      change_filter: 0,
                    },
                  ],
                  flag_setting_action: 1,
                  flag_setting_action_default: 1,
                  flag_setting_expired_date: 1,
                  flag_action_url_expired: 2,
                },
              ],
              aspect_ratio: '1.8333333333333333/1',
            },
          ],
        },
        message_media: {},
        message_stamp: {},
        message_location: {},
        message_text: {},
        message_introduction: {},
        template_group_id: template_group_id,
        template_child_id: template_child_id,
        tmp_name: '',
        action_type: 'template',
        broadcastId: '',
        scheduleSendId: '',
        conversationId: '',
        content: '',
        address: '',
        latitude: '',
        longitude: '',
      }
    end

    def build_filter(account_type)
      if account_type == 'benkyokai'
        [
          {
            active: true, modal_from_filter: '', modal_to_filter: '', day_filter_type: 0,
            id: 4050888, type: 'day_add_friend', preview: '',
            duration_day_start: '', duration_day_end: '', preview_original: '',
          },
          {
            active: true, tags_search: [1092591], tag_condition: 0, default_check_all: false,
            id: 4050889, type: 'tag',
            preview: 'タグフロントコース（延長サポート）をタグのいずれか1つ以上を含む人',
            list_tags: [{ id: 1092591, name: 'フロントコース（延長サポート）' }],
            items_default_tag: ITEMS_DEFAULT_TAG, group_open_tag: 0, tag_items: [],
            preview_original: 'フロントコース（延長サポート）',
          },
        ]
      else
        [
          {
            active: true, tags_search: [1495570], tag_condition: 0, default_check_all: false,
            id: 7969280, type: 'tag',
            preview: 'タグ前回セミナー不参加 & 受講生以外をタグのいずれか1つ以上を含む人',
            list_tags: [{ id: 1495570, name: '前回セミナー不参加 & 受講生以外' }],
            items_default_tag: ITEMS_DEFAULT_TAG, group_open_tag: 0, tag_items: [],
            preview_original: '前回セミナー不参加 & 受講生以外',
          },
          {
            active: true, tags_search: [1478703, 1620158], tag_condition: '2', default_check_all: false,
            id: 7969281, type: 'tag',
            preview: 'タグプログラミング無料体験したい・参加希望 2025-8-20をタグを1つ以上含む人を除外',
            list_tags: [
              { id: 1478703, name: 'プログラミング無料体験したい' },
              { id: 1620158, name: '参加希望 2025-8-20' },
            ],
            items_default_tag: ITEMS_DEFAULT_TAG, group_open_tag: 0, tag_items: [],
            preview_original: 'プログラミング無料体験したい・参加希望 2025-8-20',
          },
        ]
      end
    end
  end
end
