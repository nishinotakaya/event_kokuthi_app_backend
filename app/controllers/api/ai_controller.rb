require 'net/http'
require 'json'

module Api
  class AiController < ApplicationController
    OPENAI_API_URL = 'https://api.openai.com/v1/chat/completions'.freeze

    def correct
      key  = params[:apiKey].presence || ENV['OPENAI_API_KEY']
      text = params[:text]
      return render json: { error: 'OpenAI APIキーを入力してください' }, status: :bad_request unless key
      return render json: { error: 'テキストを入力してください' }, status: :bad_request unless text&.strip&.present?

      result = call_openai(key,
        system: 'あなたは文章添削のプロです。入力されたテキストを、誤字脱字の修正・表現の改善・読みやすさの向上を行い、改善版を返してください。元の意図やトーンは保ちつつ、より伝わりやすい文章にしてください。改善版のみを返し、説明は不要です。',
        user: text,
        temperature: 0.3
      )
      render json: { corrected: result }
    rescue => e
      render json: { error: e.message }, status: :internal_server_error
    end

    def generate
      key            = params[:apiKey].presence || ENV['OPENAI_API_KEY']
      title          = params[:title]
      type           = params[:type]
      event_date     = params[:eventDate]
      event_time     = params[:eventTime]     || '10:00'
      event_end_time = params[:eventEndTime]  || '12:00'
      event_sub_type = params[:eventSubType].presence
      zoom_url       = params[:zoomUrl].presence
      meeting_id     = params[:meetingId].presence
      passcode       = params[:passcode].presence

      return render json: { error: 'OpenAI APIキーを入力してください' }, status: :bad_request unless key
      return render json: { error: '名前（タイトル）を入力してください' }, status: :bad_request unless title&.strip&.present?
      return render json: { error: '開催日時の日付を入力してください' }, status: :bad_request unless event_date&.strip&.present?

      date_str = format_date(event_date, event_time, event_end_time)
      is_event = type != 'student'

      system_prompt, user_prompt = build_generate_prompts(title, is_event, event_sub_type, date_str, zoom_url, meeting_id, passcode)

      result = call_openai(key, system: system_prompt, user: user_prompt, temperature: 0.7)

      # Zoom URL 等が入力済みならプレースホルダーを置換
      result = result.gsub(/参加URL：\s*（後ほど共有）/,        "参加URL： #{zoom_url}")   if zoom_url
      result = result.gsub(/ミーティング ID:\s*（後ほど共有）/, "ミーティング ID: #{meeting_id}") if meeting_id
      result = result.gsub(/パスコード:\s*（後ほど共有）/,      "パスコード: #{passcode}")  if passcode

      render json: { content: result }
    rescue => e
      render json: { error: e.message }, status: :internal_server_error
    end

    def align_datetime
      key           = params[:apiKey].presence || ENV['OPENAI_API_KEY']
      text          = params[:text]
      event_date    = params[:eventDate]
      event_time    = params[:eventTime]    || '10:00'
      event_end_time = params[:eventEndTime] || '12:00'

      return render json: { error: 'OpenAI APIキーを入力してください' }, status: :bad_request unless key
      return render json: { content: text } unless text&.strip&.present? && event_date

      date_str = format_date(event_date, event_time, event_end_time)
      result = call_openai(key,
        system: 'あなたはテキスト編集のアシスタントです。文章中に記載されている開催日時・日付・時刻の部分のみを、指定された日時に差し替えてください。文章の他の部分は一切変更しないでください。修正後のテキスト全体のみを返してください。',
        user: "開催日時を「#{date_str}」に合わせてください。\n\n#{text}",
        temperature: 0.1
      )
      render json: { content: result }
    rescue => e
      render json: { error: e.message }, status: :internal_server_error
    end

    def agent
      key    = params[:apiKey].presence || ENV['OPENAI_API_KEY']
      text   = params[:text]
      prompt = params[:prompt]

      return render json: { error: 'OpenAI APIキーを入力してください' }, status: :bad_request unless key
      return render json: { error: '指示を入力してください' }, status: :bad_request unless prompt&.strip&.present?

      result = call_openai(key,
        system: 'あなたは文章作成のアシスタントです。ユーザーの現在のテキストに対して、ユーザーの指示に従って修正・改善した結果を返してください。結果のテキストのみを返し、余分な説明は不要です。',
        user: "【現在のテキスト】\n#{text.presence || '(空)'}\n\n【指示】\n#{prompt}",
        temperature: 0.5
      )
      render json: { result: result }
    rescue => e
      render json: { error: e.message }, status: :internal_server_error
    end

    private

    def call_openai(api_key, system:, user:, temperature: 0.5)
      uri  = URI(OPENAI_API_URL)
      req  = Net::HTTP::Post.new(uri)
      req['Authorization'] = "Bearer #{api_key}"
      req['Content-Type']  = 'application/json'
      req.body = {
        model: 'gpt-4o-mini',
        messages: [
          { role: 'system', content: system },
          { role: 'user',   content: user },
        ],
        temperature: temperature,
      }.to_json

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.read_timeout = 60

      res  = http.request(req)
      data = JSON.parse(res.body)
      raise data.dig('error', 'message') || 'OpenAI APIエラー' unless res.is_a?(Net::HTTPSuccess)

      data.dig('choices', 0, 'message', 'content')&.strip || ''
    end

    def format_date(event_date, event_time, event_end_time)
      d   = Date.parse(event_date)
      dow = %w[日 月 火 水 木 金 土][d.wday]
      "#{d.year}年#{d.month}月#{d.day}日（#{dow}） #{event_time}〜#{event_end_time}"
    end

    LINE_RULES = <<~RULES.freeze
      【LINE向け文章ルール】
      - スマホのLINEで読まれる文章です。1行は短く端的に（目安：全角20〜25文字以内）
      - 長い一文は途中で改行せず、最初から短い文に分けて書く
      - リスト項目（・✅📌）は1行で収まる長さにする。収まらない場合は内容を絞って短くする
      - 読者がスクロールせず一目で把握できる密度を意識する
      - 各セクションの間は必ず1行の空行を入れること（空行とは空の1行のこと。「（空行）」という文字を出力しないこと）
    RULES

    def build_generate_prompts(title, is_event, sub_type, date_str, zoom_url = nil, meeting_id = nil, passcode = nil)
      if !is_event
        system = 'あなたは受講生サポートのメッセージ作成プロです。タイトルに沿って、受講生に寄り添う温かみのあるサポートメッセージを生成してください。押し付けがましくなく、励ましや次のステップを示す内容にしてください。'
        user   = "以下のタイトルに沿った文章を生成してください：\n\n#{title}"
      elsif sub_type.blank?
        # LME未チェック：汎用イベント告知プロンプト
        system = "あなたはイベント告知文の作成プロです。タイトルに沿って、魅力的で読みやすいイベント告知文を生成してください。構成: 開催日時、開催形式、参加費、内容、得られること。プレーンテキストで、改行を適切に使い、見出しは■で区切ってください。【重要】開催日時は必ず「#{date_str}」をそのまま使用してください。それ以外の日付・時刻を記載しないでください。"
        user   = "【開催日時】#{date_str}\n\n上記の開催日時を文章中に必ず記載してください。日付・時刻を変えないでください。\n\nタイトル：#{title}"
      elsif sub_type == 'taiken'
        system = <<~PROMPT
          あなたはLINE配信用のイベント告知文の作成プロです。「体験会（セミナー）」の告知文を以下の構成・形式で生成してください。告知文本文のみを返し、余計な説明は不要です。マークダウン記法は使わないでください。

          #{LINE_RULES}
          【出力フォーマット（この通りの改行・空行で出力すること）】
          {タイトル}

          こんな悩みはありませんか？

          ・{悩み1}
          ・{悩み2}
          ・{悩み3}
          ・{悩み4}
          ・{悩み5}

          放置するとこんなリスクが…
          ✅ {リスク1}
          ✅ {リスク2}
          ✅ {リスク3}
          ✅ {リスク4}

          今回のセミナーで得られること
          📌 {得られること1}
          📌 {得られること2}
          📌 {得られること3}

          {クロージング1〜2文}

          開催概要
          日時：#{date_str}
          対象：プログラミングに興味がある方・初学者の方
          参加URL： （後ほど共有）

          ミーティング ID: （後ほど共有）
          パスコード: （後ほど共有）

          👉 {CTA}
        PROMPT
        user = "タイトル：#{title}\n\n開催日時は必ず「#{date_str}」をそのまま使用してください。"
      else
        # 受講生勉強会
        system = <<~PROMPT
          あなたはLINE配信用のイベント告知文の作成プロです。「受講生勉強会」の告知文を以下の構成・形式で生成してください。告知文本文のみを返し、余計な説明は不要です。マークダウン記法は使わないでください。

          #{LINE_RULES}
          【出力フォーマット（この通りの改行・空行で出力すること）】
          {タイトル}

          こんな悩みはありませんか？

          ・{悩み1}
          ・{悩み2}
          ・{悩み3}
          ・{悩み4}
          ・{悩み5}

          放置するとこんなリスクが…
          ✅ {リスク1}
          ✅ {リスク2}
          ✅ {リスク3}
          ✅ {リスク4}

          今回の勉強会で得られること
          📌 {得られること1}
          📌 {得られること2}
          📌 {得られること3}

          {クロージング1〜2文}

          開催概要
          日時：#{date_str}
          対象：プロアカ受講生
          参加URL： （後ほど共有）

          ミーティング ID: （後ほど共有）
          パスコード: （後ほど共有）

          👉 {CTA}
        PROMPT
        user = "タイトル：#{title}\n\n開催日時は必ず「#{date_str}」をそのまま使用してください。"
      end
      [system, user]
    end
  end
end
