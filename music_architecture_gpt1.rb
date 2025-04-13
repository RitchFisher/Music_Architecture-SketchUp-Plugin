require 'sketchup.rb'

module MusicArchitecture
  class Main
    def initialize
      @dialog = nil
    end

    def show_dialog
      return if @dialog && @dialog.visible?
      
      # 创建 HTML 面板内容
      html_content = get_html_content
      
      # 创建对话框
      @dialog = UI::HtmlDialog.new({
        :dialog_title => 'Music Architecture',
        :preferences_key => 'com.musicarchitecture',
        :width => 400,
        :height => 600,
        :left => 150,
        :top => 150,
        :resizable => true
      })
      @dialog.set_html(html_content)
      
      # 在对话框关闭时的回调
      @dialog.add_action_callback('close') do |dialog, params|
        dialog.close
      end

      # 显示面板
      @dialog.show
    end

    def get_html_content
      <<~HTML
        <html>
        <body>
          <h2>Music Architecture 面板</h2>
          <p>当前组: <span id="group_id">未选择</span></p>
          <form id="paramsForm">
            <label>长度 (X): <input type="text" id="length" value="600"></label><br>
            <label>宽度 (Y): <input type="text" id="width" value="100"></label><br>
            <label>高度 (Z): <input type="text" id="height" value="3000"></label><br>
            <label>行进方向: <input type="text" id="advance_dir" value="Y"></label><br>
            <label>旋转轴: <input type="text" id="rotation_axis" value="Z"></label><br>
            <label>标准间距: <input type="text" id="spacing" value="600"></label><br>
            <button type="button" onclick="createNewGroup()">创建新组</button>
            <button type="button" onclick="updateCurrentGroup()">保存到当前组</button>
          </form>
          <h3>当前参考点</h3>
          <p>X: <input type="text" id="ref_x" value="0"></p>
          <p>Y: <input type="text" id="ref_y" value="0"></p>
          <p>Z: <input type="text" id="ref_z" value="0"></p>
          <button onclick="updateReferencePoint()">更新参考点</button>
          <button onclick="switchGroup('prev')">前一组</button>
          <button onclick="switchGroup('next')">后一组</button>
          <h3>放置音符</h3>
          <button onclick="placeNote('z')">C (0°)</button>
          <button onclick="placeNote('s')">#C (15°)</button>
          <
