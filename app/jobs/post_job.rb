require 'playwright'
require 'net/http'
require 'open-uri'
require 'json'
require 'shellwords'

class PostJob < ApplicationJob
  queue_as :default

  def perform(job_id, payload)
    content        = payload['content'].to_s
    sites          = Array(payload['sites'])
    event_fields   = payload['eventFields'] || {}
    generate_image = payload['generateImage']
    image_style    = payload['imageStyle'] || 'cute'
    openai_key     = payload['openaiApiKey'].presence || ENV['OPENAI_API_KEY']

    broadcast(job_id, type: 'log', message: '投稿処理を開始します...')

    # ===== 画像生成（DALL-E 3） =====
    image_path = nil
    if generate_image
      if openai_key.blank?
        broadcast(job_id, type: 'log', message: '⚠️ 画像生成: OpenAI APIキーが未設定のためスキップします')
      else
        begin
          broadcast(job_id, type: 'log', message: '🖼️ DALL-E 3で画像生成中...')
          image_title = event_fields['title'].presence || content.split("\n").first.to_s[0, 80]
          image_path  = generate_dalle_image(openai_key, image_title, image_style, job_id)
          broadcast(job_id, type: 'log', message: '🖼️ 画像生成・保存完了')
        rescue => e
          broadcast(job_id, type: 'log', message: "⚠️ 画像生成失敗: #{e.message}")
        end
      end
    end

    playwright_path = find_playwright_path

    Playwright.create(playwright_cli_executable_path: playwright_path) do |playwright|
      browser = playwright.chromium.launch(
        headless: true,
        args: ['--no-sandbox', '--disable-setuid-sandbox', '--disable-blink-features=AutomationControlled'],
      )

      broadcast(job_id, type: 'log', message: "🚀 #{sites.length}サイトを並列投稿開始...")

      # ===== サイトごとに独立コンテキストで並列実行 =====
      threads = sites.map do |site_key|
        Thread.new do
          site_name, sub_type = site_key.split(':', 2)
          ef = event_fields.merge(
            'lmeAccount' => (sub_type || event_fields['lmeAccount'] || 'taiken'),
            'imagePath'  => image_path,
          )

          context = browser.new_context(
            userAgent: 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/145.0.0.0 Safari/537.36',
            locale: 'ja-JP',
            viewport: { width: 1280, height: 800 },
          )
          page = context.new_page

          broadcast(job_id, type: 'status', site: site_name, status: 'running')
          broadcast(job_id, type: 'log',    message: "[#{site_name}] 開始...")

          begin
            log_fn = ->(msg) { broadcast(job_id, type: 'log', message: msg) }

            case site_name
            when 'こくチーズ' then Posting::KokuchproService.new.call(page, content, ef, &log_fn)
            when 'Peatix'     then Posting::PeatixService.new.call(page, content, ef, &log_fn)
            when 'connpass'   then Posting::ConnpassService.new.call(page, content, ef, &log_fn)
            when 'LME'        then Posting::LmeService.new.call(page, content, ef, &log_fn)
            when 'TechPlay'   then Posting::TechplayService.new.call(page, content, ef, &log_fn)
            else broadcast(job_id, type: 'log', message: "[#{site_name}] 未対応サイトです")
            end

            broadcast(job_id, type: 'status', site: site_name, status: 'success')
          rescue => e
            broadcast(job_id, type: 'log',    message: "[#{site_name}] ❌ エラー: #{e.message}")
            broadcast(job_id, type: 'status', site: site_name, status: 'error')
          ensure
            context.close rescue nil
          end
        end
      end

      threads.each(&:join)
      browser.close rescue nil
    end

    broadcast(job_id, type: 'log', message: '✅ 全サイト処理完了')
    broadcast(job_id, type: 'done')
  rescue => e
    broadcast(job_id, type: 'error', message: e.message)
    broadcast(job_id, type: 'done')
  ensure
    File.delete(image_path) if image_path && File.exist?(image_path) rescue nil
  end

  private

  def broadcast(job_id, data)
    ActionCable.server.broadcast("post_#{job_id}", data)
  end

  def find_playwright_path
    local = Rails.root.join('node_modules', '.bin', 'playwright').to_s
    if File.exist?(local)
      # パスにスペースや日本語が含まれる場合、ラッパースクリプト経由で実行
      wrapper = '/tmp/playwright-runner.sh'
      unless File.exist?(wrapper)
        File.write(wrapper, "#!/bin/bash\nexec #{Shellwords.escape(local)} \"$@\"\n")
        File.chmod(0o755, wrapper)
      end
      return wrapper
    end
    # グローバルの npx を使用
    npx = `which npx`.strip
    npx.present? ? "#{npx} playwright" : 'npx playwright'
  end

  def generate_dalle_image(api_key, title, image_style, job_id)
    is_cute = image_style != 'cool'
    style_prompt = is_cute ?
      "Cute and kawaii style event banner for \"#{title}\". Pastel colors, soft watercolor illustration, adorable characters or flowers, warm and friendly atmosphere. No text. High quality." :
      "Cool and stylish event banner for \"#{title}\". Bold colors, modern geometric design, dynamic composition, sharp and professional look. No text. High quality."

    broadcast(job_id, type: 'log', message: "🖼️ スタイル: #{is_cute ? '🌸 可愛い系' : '⚡ かっこいい系'}")

    uri = URI('https://api.openai.com/v1/images/generations')
    req = Net::HTTP::Post.new(uri)
    req['Authorization'] = "Bearer #{api_key}"
    req['Content-Type']  = 'application/json'
    req.body = { model: 'dall-e-3', prompt: style_prompt, n: 1, size: '1024x1024' }.to_json

    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.read_timeout = 120

    res  = http.request(req)
    data = JSON.parse(res.body)
    raise data.dig('error', 'message') || 'DALL-E APIエラー' unless res.is_a?(Net::HTTPSuccess)

    image_url = data.dig('data', 0, 'url')
    raise '画像URLが取得できませんでした' unless image_url

    broadcast(job_id, type: 'log', message: '🖼️ 画像URL取得完了。ダウンロード中...')
    image_data  = URI.open(image_url).read # rubocop:disable Security/Open
    image_path  = Rails.root.join('tmp', "event_image_#{Time.now.to_i}_#{job_id}.png").to_s
    File.write(image_path, image_data, mode: 'wb')
    image_path
  end
end
