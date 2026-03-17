module Posting
  class KokuchproService < BaseService
    CREATE_URL = 'https://www.kokuchpro.com/regist/'

    FILL_FIELDS_JS = <<~'JS'
      (args) => {
        const { title, summary80, ymdDash, ymdEndDash, entry7, entry1,
                tStart, tEnd, cap, place, zoomUrl, tel, email } = args;
        const logs = [];
        const $ = window.jQuery || window.$ || null;

        const find = (...sels) => {
          for (const s of sels) {
            try { const el = document.querySelector(s); if (el) return el; } catch (_) {}
          }
          return null;
        };

        const setSelectOpt = (el, v) => {
          if (!el || el.tagName !== 'SELECT') return false;
          const ival = parseInt(v);
          for (const o of el.options) {
            if (o.value === String(v)) { el.value = o.value; el.dispatchEvent(new Event('change', { bubbles: true })); return true; }
          }
          for (const o of el.options) {
            if (parseInt(o.value) === ival && !isNaN(ival)) { el.value = o.value; el.dispatchEvent(new Event('change', { bubbles: true })); return true; }
          }
          return false;
        };

        const setDate = (el, ymd) => {
          if (!el) return 'NOT_FOUND';
          el.removeAttribute('disabled'); el.removeAttribute('readonly');
          const [yr, mo, dy] = ymd.split('-').map(Number);
          if ($ && $.fn && $.fn.datepicker && el.classList.contains('hasDatepicker')) {
            try {
              $(el).datepicker('setDate', new Date(yr, mo - 1, dy));
              el.dispatchEvent(new Event('input', { bubbles: true }));
              return 'jq:' + el.value;
            } catch (e) {}
          }
          el.value = ymd;
          el.dispatchEvent(new Event('input',  { bubbles: true }));
          el.dispatchEvent(new Event('change', { bubbles: true }));
          el.dispatchEvent(new Event('blur',   { bubbles: true }));
          return 'direct:' + el.value;
        };

        const setTime = (baseName, timeStr) => {
          const [h, m] = timeStr.split(':');
          const el = find(`[name="${baseName}"]`);
          if (el) {
            if (el.tagName === 'SELECT') {
              setSelectOpt(el, timeStr) || setSelectOpt(el, `${parseInt(h)}:${m}`) || setSelectOpt(el, h);
              return 'select:' + el.value;
            }
            el.value = timeStr;
            el.dispatchEvent(new Event('input',  { bubbles: true }));
            el.dispatchEvent(new Event('change', { bubbles: true }));
            return 'input:' + el.value;
          }
          const hEl = find(`[name="${baseName}[hour]"]`);
          const mEl = find(`[name="${baseName}[min]"]`);
          if (hEl) setSelectOpt(hEl, h);
          if (mEl) setSelectOpt(mEl, m);
          return `sub:${hEl?.value}:${mEl?.value}`;
        };

        const setVal = (el, v) => {
          if (!el) return false;
          el.removeAttribute('disabled'); el.removeAttribute('readonly');
          const proto = el.tagName === 'TEXTAREA' ? HTMLTextAreaElement.prototype : HTMLInputElement.prototype;
          const setter = Object.getOwnPropertyDescriptor(proto, 'value')?.set;
          if (setter) setter.call(el, String(v)); else el.value = String(v);
          el.dispatchEvent(new Event('input',  { bubbles: true }));
          el.dispatchEvent(new Event('change', { bubbles: true }));
          return true;
        };

        const nameEl = find('#EventName', '[name="data[Event][name]"]');
        setVal(nameEl, title);
        logs.push(`name: ${nameEl ? '"' + nameEl.value.slice(0, 30) + '"' : 'NOT_FOUND'}`);

        const descEl = find('#EventDescription', '[name="data[Event][description]"]');
        if (descEl) {
          const hasTiny = typeof tinymce !== 'undefined' && tinymce.get && tinymce.get(descEl.id);
          if (hasTiny) { hasTiny.setContent(summary80); hasTiny.save(); logs.push('description: TinyMCE設定'); }
          else { setVal(descEl, summary80); logs.push(`description: ${descEl.value.length}文字`); }
        } else { logs.push('description: NOT_FOUND'); }

        const genreEl = find('[name="data[Event][genre]"]', '#EventGenre');
        if (genreEl && genreEl.tagName === 'SELECT') {
          const opt = [...genreEl.options].find(o => o.value && o.value !== '' && o.value !== '0');
          if (opt) { genreEl.value = opt.value; genreEl.dispatchEvent(new Event('change', { bubbles: true })); }
        }

        logs.push(`start_date: ${setDate(find('#EventDateStartDateDate', '[name="data[EventDate][start_date_date]"]'), ymdDash)}`);
        logs.push(`end_date:   ${setDate(find('#EventDateEndDateDate',   '[name="data[EventDate][end_date_date]"]'),   ymdEndDash)}`);
        logs.push(`start_time: ${setTime('data[EventDate][start_date_time]', tStart)}`);
        logs.push(`end_time:   ${setTime('data[EventDate][end_date_time]',   tEnd)}`);
        logs.push(`entry_start: ${setDate(find('#EventDateEntryStartDateDate', '[name="data[EventDate][entry_start_date_date]"]'), entry7)}`);
        logs.push(`entry_end:   ${setDate(find('#EventDateEntryEndDateDate',   '[name="data[EventDate][entry_end_date_date]"]'),   entry1)}`);
        logs.push(`entry_start_time: ${setTime('data[EventDate][entry_start_date_time]', '00:00')}`);
        logs.push(`entry_end_time:   ${setTime('data[EventDate][entry_end_date_time]',   '23:59')}`);

        setVal(find('#EventDateTotalCapacity', '[name="data[EventDate][total_capacity]"]'), cap);
        setVal(find('#EventPlace',             '[name="data[Event][place]"]'),              place);
        if (zoomUrl) setVal(find('#EventPlaceUrl', '[name="data[Event][place_url]"]'), zoomUrl);
        const countryEl = find('[name="data[Event][country]"]');
        if (countryEl) setSelectOpt(countryEl, 'JPN');
        setVal(find('#EventTel',   '[name="data[Event][tel]"]'),   tel);
        setVal(find('#EventEmail', '[name="data[Event][email]"]'), email);

        return logs;
      }
    JS

    private

    def execute(page, content, ef)
      title = extract_title(ef, content)

      log("[こくチーズ] /regist/ にアクセス中...")
      page.goto(CREATE_URL, waitUntil: 'domcontentloaded', timeout: 30_000)
      page.wait_for_timeout(1500)

      # Login if redirected
      if page.url.include?('login') || page.url.include?('signin')
        log("[こくチーズ] ログイン中...")
        page.fill('#LoginFormEmail', ENV['CONPASS__KOKUCIZE_MAIL'].to_s)
        page.fill('#LoginFormPassword', ENV['CONPASS_KOKUCIZE_PASSWORD'].to_s)
        page.expect_navigation(timeout: 30_000) { page.click('#UserLoginForm button[type="submit"]') } rescue nil
        page.wait_for_load_state('networkidle', timeout: 20_000) rescue nil
        raise "ログインに失敗しました" if page.url.include?('login') || page.url.include?('signin')
        log("[こくチーズ] ✅ ログイン完了 → #{page.url}")
      else
        log("[こくチーズ] ✅ ログイン済み")
      end

      # Step1: event type + fee
      has_step1 = page.locator('input[name="data[Event][event_type]"]').first.visible?(timeout: 2_000) rescue false
      if has_step1
        log("[こくチーズ] Step1: イベント種別選択")
        page.locator('input[name="data[Event][event_type]"][value="0"]').check rescue nil
        page.locator('input[name="data[Event][charge]"][value="0"]').check rescue nil
        page.evaluate(<<~JS)
          const f = [...document.querySelectorAll('form')].find(f => f.querySelector('input[name="data[step]"]'));
          if (f) f.submit();
        JS
        page.wait_for_load_state('networkidle', timeout: 20_000) rescue nil
        log("[こくチーズ] Step2へ → #{page.url}")
      end

      page.wait_for_timeout(2500)

      # Date/time setup
      start_date = ef['startDate'].present? ? normalize_date(ef['startDate']) : default_date_plus(30)
      end_date   = ef['endDate'].present?   ? normalize_date(ef['endDate'])   : start_date
      t_start = pad_time(ef['startTime'] || '10:00')
      t_end   = pad_time(ef['endTime']   || '12:00')
      place   = ef['place'].presence || 'オンライン'
      cap     = ef['capacity'].presence || '50'
      tel     = parse_tel(ef['tel'])
      entry7  = (Date.parse(start_date) - 7).strftime('%Y-%m-%d')
      entry1  = (Date.parse(start_date) - 1).strftime('%Y-%m-%d')
      summary80 = content.gsub("\n", ' ').gsub(/\s+/, ' ').strip[0, 80].presence || 'イベントのご案内です。'

      # TinyMCE content
      tiny_result = page.evaluate("(html) => { if (typeof tinymce === 'undefined' || !tinymce.editors || tinymce.editors.length === 0) return []; const results = []; tinymce.editors.forEach(ed => { const id = (ed.id || '').toLowerCase(); if (id.includes('body') || id.includes('page') || id.includes('html')) { ed.setContent(html.replace(/\\n/g, '<br>')); ed.save(); results.push({ id: ed.id, role: 'body' }); } else { results.push({ id: ed.id, role: 'other' }); } }); return results; }", arg: content) rescue []
      log("[こくチーズ] TinyMCEエディタ: #{tiny_result.to_json}") if tiny_result&.length.to_i > 0

      # Fill all fields
      fill_args = {
        title: title, summary80: summary80,
        ymdDash: start_date, ymdEndDash: end_date,
        entry7: entry7, entry1: entry1,
        tStart: t_start, tEnd: t_end,
        cap: cap, place: place,
        zoomUrl: ef['zoomUrl'].to_s,
        tel: tel, email: ENV['CONPASS__KOKUCIZE_MAIL'].to_s,
      }
      fill_result = page.evaluate(FILL_FIELDS_JS, arg: fill_args)
      Array(fill_result).each { |l| log("[こくチーズ] #{l}") }

      # Sub-genre
      page.wait_for_timeout(600)
      page.evaluate("const sel = document.querySelector('#EventGenreSub, [name=\"data[Event][genre_sub]\"]'); if (sel && sel.tagName === 'SELECT') { const opt = [...sel.options].find(o => o.value && o.value !== '' && o.value !== '0'); if (opt) { sel.value = opt.value; sel.dispatchEvent(new Event('change', { bubbles: true })); } }") rescue nil

      # Daily limit check
      page_text = page.evaluate("document.documentElement.textContent || ''")
      if page_text.include?('登録数が制限') || page_text.include?('1日最大') || page_text.include?('明日以降にイベント')
        raise "日次制限エラー: こくちーずの1日3件制限に達しました"
      end

      # Find submit button
      reg_btn = page.evaluate(<<~JS)
        (() => {
          const submits = [...document.querySelectorAll('input[type="submit"]')];
          const reg = submits.find(b => { const v = b.value || ''; return !v.includes('選び直す') && !v.includes('戻る') && !v.includes('キャンセル') && !v.includes('検索'); });
          if (reg) return { tag: 'INPUT', value: reg.value, selector: `input[type="submit"][value="${reg.value}"]` };
          const btns = [...document.querySelectorAll('button[type="submit"]')];
          const regBtn = btns.find(b => { const form = b.closest('form'); return form && form.querySelector('[name="data[EventDate][start_date_date]"]'); });
          if (regBtn) return { tag: 'BUTTON', value: regBtn.textContent?.trim() || '', selector: null };
          return { tag: null };
        })()
      JS

      log("[こくチーズ] 登録ボタン: #{reg_btn.to_json}")
      raise "送信ボタンが見つかりません" unless reg_btn['tag']

      submit_btn = if reg_btn['selector']
        page.locator(reg_btn['selector']).first
      else
        event_form = page.locator('form').filter(has: page.locator('[name="data[EventDate][start_date_date]"]'))
        event_form.locator('button[type="submit"]').first
      end

      submit_btn.scroll_into_view_if_needed rescue nil
      log("[こくチーズ] 送信: \"#{reg_btn['value']}\"")
      page.expect_navigation(timeout: 30_000) { submit_btn.click } rescue nil
      page.wait_for_load_state('networkidle', timeout: 20_000) rescue nil

      if page.url.include?('/regist/')
        errors = page.evaluate("[...document.querySelectorAll('.error-message, [class*=\"error\"], .alert, .alert-error')].map(el => el.textContent.trim()).filter(Boolean).join(' / ')") rescue ''
        raise "登録失敗: #{errors.presence || '不明'}"
      end

      log("[こくチーズ] ✅ 投稿完了 → #{page.url}")
    end

    def parse_tel(raw)
      return '03-1234-5678' if raw.blank?
      raw =~ /^\d{2,4}-\d{4}-\d{4}$/ ? raw : '03-1234-5678'
    end
  end
end
