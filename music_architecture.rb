require 'sketchup.rb'
require 'extensions.rb'

module MusicArchitecture
  # 默认参数
  @base_length = 600.0
  @base_width = 100.0
  @base_height = 3000.0
  @advance_dir = 'Y'
  @rotation_axis = 'Z'
  @reference_point = Geom::Point3d.new(0, 0, 0)
  @current_note = "Full Note"

  # HtmlDialog
  @dialog = nil

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
        height: 500,
        left: 100,
        top: 100,
        resizable: true
      )
      @dialog.set_html(get_html_content)
      @dialog.add_action_callback("setParams") { |_, params| set_parameters(params) }
      @dialog.add_action_callback("enterEditMode") { |_| Sketchup.active_model.select_tool(MusicTool.new) }
      @dialog.add_action_callback("setReferencePoint") { |_, x, y, z| @reference_point = Geom::Point3d.new(x.to_f, y.to_f, z.to_f) }
      @dialog.add_action_callback("placeNote") { |_, key| place_note(key) }
      @dialog.add_action_callback("setNoteType") { |_, key| set_note_type(key) }
      @dialog.add_action_callback("advanceReferencePoint") { |_| advance_reference_point }
      @dialog.show
    end
  end

  # 设置参数
  def self.set_parameters(params)
    @base_length = params['length'].to_f
    @base_width = params['width'].to_f
    @base_height = params['height'].to_f
    @advance_dir = params['advance_dir'].upcase
    @rotation_axis = params['rotation_axis'].upcase
    create_note_components
  end

  # 创建音符组件
  def self.create_note_components
    model = Sketchup.active_model
    definitions = model.definitions
    definitions.purge_unused

    note_types = {
      "Full Note" => 1.0,
      "Half Note" => 0.5,
      "Quarter Note" => 0.25,
      "Eighth Note" => 0.125,
      "Sixteenth Note" => 0.0625
    }

    note_types.each do |name, factor|
      definition = definitions[name]
      if definition
        definition.entities.clear!
      else
        definition = definitions.add(name)
      end
      length = @base_length * factor
      create_rectangle(definition, length, @base_width, @base_height)
    end
  end

  # 创建长方体（几何中心对齐原点）
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

  # 编辑模式工具类
  class MusicTool
    def activate
      UI.messagebox("已进入编辑模式，使用面板按钮操作。")
    end

    def deactivate(view)
      UI.messagebox("已退出编辑模式。")
    end
  end

  # 放置音符
  def self.place_note(key)
    note_map = {
      'z' => 0, 's' => 15, 'x' => 30, 'd' => 45, 'c' => 60, 'v' => 75,
      'g' => 90, 'b' => 105, 'h' => 120, 'n' => 135, 'j' => 150, 'm' => 165
    }
    angle = note_map[key]
    model = Sketchup.active_model
    entities = model.active_entities
    definition = model.definitions[@current_note]
    instance = entities.add_instance(definition, @reference_point)

    axis = case @rotation_axis
           when 'X' then [1, 0, 0]
           when 'Y' then [0, 1, 0]
           when 'Z' then [0, 0, 1]
           end
    tr = Geom::Transformation.rotation(@reference_point, axis, angle.degrees)
    instance.transform!(tr)

    advance_reference_point
  end

  # 移动参考点
  def self.advance_reference_point
    spacing = get_current_spacing
    vector = case @advance_dir
             when 'X' then [spacing, 0, 0]
             when 'Y' then [0, spacing, 0]
             when 'Z' then [0, 0, spacing]
             end
    @reference_point += vector
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

  # 获取当前间距
  def self.get_current_spacing
    factor = {
      "Full Note" => 1.0,
      "Half Note" => 0.5,
      "Quarter Note" => 0.25,
      "Eighth Note" => 0.125,
      "Sixteenth Note" => 0.0625
    }
    @base_length * factor[@current_note]
  end

  # HTML内容
  def self.get_html_content
    <<~HTML
      <html>
      <body>
        <h2>Music Architecture 面板</h2>
        <form id="paramsForm">
          <label>长度 (X): <input type="text" id="length" value="#{@base_length}"></label><br>
          <label>宽度 (Y): <input type="text" id="width" value="#{@base_width}"></label><br>
          <label>高度 (Z): <input type="text" id="height" value="#{@base_height}"></label><br>
          <label>行进方向: <input type="text" id="advance_dir" value="#{@advance_dir}"></label><br>
          <label>旋转轴: <input type="text" id="rotation_axis" value="#{@rotation_axis}"></label><br>
          <button type="button" onclick="setParams()">设置参数</button>
        </form>
        <h3>当前参考点</h3>
        <p>X: <input type="text" id="ref_x" value="#{@reference_point.x}"></p>
        <p>Y: <input type="text" id="ref_y" value="#{@reference_point.y}"></p>
        <p>Z: <input type="text" id="ref_z" value="#{@reference_point.z}"></p>
        <button onclick="updateReferencePoint()">更新参考点</button>
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
            rotation_axis: document.getElementById('rotation_axis').value
          };
          sketchup.setParams(params);
        }
        function updateReferencePoint() {
          var x = document.getElementById('ref_x').value;
          var y = document.getElementById('ref_y').value;
          var z = document.getElementById('ref_z').value;
          sketchup.setReferencePoint(x, y, z);
        }
        function enterEditMode() { sketchup.enterEditMode(); }
        function placeNote(key) { sketchup.placeNote(key); }
        function setNoteType(key) { sketchup.setNoteType(key); }
        function advanceReferencePoint() { sketchup.advanceReferencePoint(); }
      </script>
      </html>
    HTML
  end
end