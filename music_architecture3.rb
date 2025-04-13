require 'sketchup.rb'
require 'extensions.rb'

module MusicArchitecture
  @versions = []
  @current_version_index = -1
  @current_note = "Full Note"

  # 添加菜单项
  unless file_loaded?(__FILE__)
    menu = UI.menu('Plugins')
    menu.add_item('Show Music Architecture Panel') { show_panel }
    file_loaded(__FILE__)
  end

  # 显示面板
  def self.show_panel
    if @dialog.nil? || !@dialog.visible?
      @dialog = UI::HtmlDialog.new(
        dialog_title: "Music Architecture",
        preferences_key: "MusicArchitecturePanel",
        width: 350,
        height: 600,
        left: 100,
        top: 100,
        resizable: true
      )
      @dialog.set_html(get_html_content)
      @dialog.add_action_callback("setParams") { |_, params| set_parameters(params) }
      @dialog.add_action_callback("enterEditMode") { |_| Sketchup.active_model.select_tool(MusicTool.new) }
      @dialog.add_action_callback("setReferencePoint") { |_, x, y, z| set_reference_point(x, y, z) }
      @dialog.add_action_callback("placeNote") { |_, key| place_note(key) }
      @dialog.add_action_callback("setNoteType") { |_, key| set_note_type(key) }
      @dialog.add_action_callback("advanceReferencePoint") { |_| advance_reference_point }
      @dialog.add_action_callback("switchVersion") { |_, direction| switch_version(direction) }
      @dialog.show
    end
  end

  # 设置参数并创建新版本
  def self.set_parameters(params)
    new_version = {
      length: params['length'].to_f,
      width: params['width'].to_f,
      height: params['height'].to_f,
      advance_dir: params['advance_dir'].upcase,
      rotation_axis: params['rotation_axis'].upcase,
      base_spacing: params['spacing'].to_f,
      reference_point: Geom::Point3d.new(0, 0, 0),  # 默认参考点
      note_components: {}
    }
    create_note_components(new_version)
    @versions << new_version
    @current_version_index = @versions.size - 1
    update_panel_display
  end

  # 创建音符组件
  def self.create_note_components(version)
    model = Sketchup.active_model
    definitions = model.definitions
    note_types = {
      "Full Note" => 1.0,
      "Half Note" => 0.5,
      "Quarter Note" => 0.25,
      "Eighth Note" => 0.125,
      "Sixteenth Note" => 0.0625
    }
    version[:note_components] = {}
    note_types.each do |name, factor|
      component_name = "#{name} v#{@versions.size + 1}"  # 例如 "Full Note v1"
      definition = definitions.add(component_name)
      length = version[:length] * factor
      create_rectangle(definition, length, version[:width], version[:height])
      version[:note_components][name] = component_name
    end
  end

  # 创建长方体
  def self.create_rectangle(definition, length, width, height)
    entities = definition.entities
    points = [
      [-length/2, -width/2, -height/2],
      [length/2, -width/2, -height/2],
      [length/2, width/2, -height/2],
      [-length/2, width/2, -height/2]
    ]
    face = entities.add_face(points)
    face.pushpull(height)
  end

  # 设置参考点
  def self.set_reference_point(x, y, z)
    if @current_version_index >= 0
      @versions[@current_version_index][:reference_point] = Geom::Point3d.new(x.to_f, y.to_f, z.to_f)
      update_panel_display
    end
  end

  # 切换版本
  def self.switch_version(direction)
    if direction == "prev" && @current_version_index > 0
      @current_version_index -= 1
    elsif direction == "next" && @current_version_index < @versions.size - 1
      @current_version_index += 1
    end
    update_panel_display
  end

  # 更新面板显示
  def self.update_panel_display
    if @current_version_index >= 0
      version = @versions[@current_version_index]
      @dialog.execute_script("document.getElementById('length').value = '#{version[:length]}';")
      @dialog.execute_script("document.getElementById('width').value = '#{version[:width]}';")
      @dialog.execute_script("document.getElementById('height').value = '#{version[:height]}';")
      @dialog.execute_script("document.getElementById('advance_dir').value = '#{version[:advance_dir]}';")
      @dialog.execute_script("document.getElementById('rotation_axis').value = '#{version[:rotation_axis]}';")
      @dialog.execute_script("document.getElementById('spacing').value = '#{version[:base_spacing]}';")
      @dialog.execute_script("document.getElementById('ref_x').value = '#{version[:reference_point].x}';")
      @dialog.execute_script("document.getElementById('ref_y').value = '#{version[:reference_point].y}';")
      @dialog.execute_script("document.getElementById('ref_z').value = '#{version[:reference_point].z}';")
    end
  end

  # 放置音符
  def self.place_note(key)
    if @current_version_index < 0
      UI.messagebox("请先设置参数")
      return
    end
    version = @versions[@current_version_index]
    note_map = {
      'z' => 0, 's' => 15, 'x' => 30, 'd' => 45, 'c' => 60, 'v' => 75,
      'g' => 90, 'b' => 105, 'h' => 120, 'n' => 135, 'j' => 150, 'm' => 165
    }
    angle = note_map[key]
    model = Sketchup.active_model
    entities = model.active_entities
    component_name = version[:note_components][@current_note]
    instance = entities.add_instance(model.definitions[component_name], version[:reference_point])

    axis = case version[:rotation_axis]
           when 'X' then [1, 0, 0]
           when 'Y' then [0, 1, 0]
           when 'Z' then [0, 0, 1]
           end
    tr = Geom::Transformation.rotation(version[:reference_point], axis, angle.degrees)
    instance.transform!(tr)

    advance_reference_point
  end

  # 移动参考点
  def self.advance_reference_point
    if @current_version_index < 0
      return
    end
    version = @versions[@current_version_index]
    factor = {
      "Full Note" => 1.0,
      "Half Note" => 0.5,
      "Quarter Note" => 0.25,
      "Eighth Note" => 0.125,
      "Sixteenth Note" => 0.0625
    }
    spacing = version[:base_spacing] * factor[@current_note]
    vector = case version[:advance_dir]
             when 'X' then [spacing, 0, 0]
             when 'Y' then [0, spacing, 0]
             when 'Z' then [0, 0, spacing]
             end
    version[:reference_point] += vector
    update_panel_display
  end

  # 设置音符类型
  def self.set_note_type(key)
    note_types = {
      '1' => "Full Note",
      '2' => "Half Note",
      '3' => "Quarter Note",
      '4' => "Eighth Note",
      '5' => "Sixteenth Note"
    }
    @current_note = note_types[key]
  end

  # HTML内容
  def self.get_html_content
    <<~HTML
      <html>
      <body>
        <h2>Music Architecture 面板</h2>
        <form id="paramsForm">
          <label>长度 (X): <input type="text" id="length" value="600"></label><br>
          <label>宽度 (Y): <input type="text" id="width" value="100"></label><br>
          <label>高度 (Z): <input type="text" id="height" value="3000"></label><br>
          <label>行进方向: <input type="text" id="advance_dir" value="Y"></label><br>
          <label>旋转轴: <input type="text" id="rotation_axis" value="Z"></label><br>
          <label>标准间距: <input type="text" id="spacing" value="600"></label><br>
          <button type="button" onclick="setParams()">设置参数</button>
        </form>
        <h3>当前参考点</h3>
        <p>X: <input type="text" id="ref_x" value="0"></p>
        <p>Y: <input type="text" id="ref_y" value="0"></p>
        <p>Z: <input type="text" id="ref_z" value="0"></p>
        <button onclick="updateReferencePoint()">更新参考点</button>
        <h3>版本切换</h3>
        <button onclick="switchVersion('prev')">前一组</button>
        <button onclick="switchVersion('next')">后一组</button>
        <button onclick="enterEditMode()">进入编辑模式</button>
        <h3>放置音符</h3>
        <button onclick="placeNote('z')">C (0°)</button>
        <button onclick="placeNote('s')">#C (15°)</button>
        <button onclick="placeNote('x')">D (30°)</button>
        <button onclick="placeNote('d')">#D (45°)</button>
        <button onclick="placeNote('c')">E (60°)</button>
        <button onclick="placeNote('v')">F (75°)</button>
        <button onclick="placeNote('g')">#F (90°)</button>
        <button onclick="placeNote('b')">G (105°)</button>
        <button onclick="placeNote('h')">#G (120°)</button>
        <button onclick="placeNote('n')">A (135°)</button>
        <button onclick="placeNote('j')">#A (150°)</button>
        <button onclick="placeNote('m')">B (165°)</button>
        <h3>选择音符类型</h3>
        <button onclick="setNoteType('1')">全音符</button>
        <button onclick="setNoteType('2')">二分音符</button>
        <button onclick="setNoteType('3')">四分音符</button>
        <button onclick="setNoteType('4')">八分音符</button>
        <button onclick="setNoteType('5')">十六分音符</button>
        <h3>空拍</h3>
        <button onclick="advanceReferencePoint()">空拍 (0)</button>
      </body>
      <script>
        function setParams() {
          var params = {
            length: document.getElementById('length').value,
            width: document.getElementById('width').value,
            height: document.getElementById('height').value,
            advance_dir: document.getElementById('advance_dir').value,
            rotation_axis: document.getElementById('rotation_axis').value,
            spacing: document.getElementById('spacing').value
          };
          sketchup.setParams(params);
        }
        function updateReferencePoint() {
          var x = document.getElementById('ref_x').value;
          var y = document.getElementById('ref_y').value;
          var z = document.getElementById('ref_z').value;
          sketchup.setReferencePoint(x, y, z);
        }
        function switchVersion(direction) {
          sketchup.switchVersion(direction);
        }
        function enterEditMode() { sketchup.enterEditMode(); }
        function placeNote(key) { sketchup.placeNote(key); }
        function setNoteType(key) { sketchup.setNoteType(key); }
        function advanceReferencePoint() { sketchup.advanceReferencePoint(); }
      </script>
      </html>
    HTML
  end

  # 编辑模式工具类
  class MusicTool
    def activate
      UI.messagebox("已进入编辑模式，使用面板按钮操作。")
    end

    def deactivate(view)
      UI.messagebox("已退出编辑模式。")
    end
  end
end