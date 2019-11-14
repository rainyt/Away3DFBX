package away3d.loaders.parsers{
	import flash.geom.Matrix3D;
	import flash.geom.Vector3D;
	import flash.utils.ByteArray;
	import flash.utils.Dictionary;
	import flash.utils.Endian;
	
	import away3d.arcane;
	import away3d.animators.data.Skeleton;
	import away3d.animators.data.SkeletonPose;
	import away3d.cameras.Camera3D;
	import away3d.core.base.Geometry;
	import away3d.core.base.SubGeometry;
	import away3d.entities.Mesh;
	import away3d.lights.DirectionalLight;
	import away3d.lights.LightBase;
	import away3d.lights.PointLight;
	import away3d.loaders.misc.ResourceDependency;
	import away3d.materials.MaterialBase;

	use namespace arcane;
	
	public class FBXParser extends ParserBase{
		private var scale:Number = 1;
		private var fbx_templates:Array;
		private var fbx_table_nodes:Array;
		private var fbx_connections_map_reverse:Array;
		private var fbx_connections_map:Array;
		private var fbx_item:Array;
		
		private var _skeleton:Skeleton;
		private var _skeletonPose:SkeletonPose;
		private var fbx_helper_nodes:Array;
		
		public function FBXParser(
			filePath:String = "", 
			use_manual_orientation:Boolean = false,
			axis_forward:String = "-Z",
			axis_up:String = "Y",
			global_scale:Number = 1,
			use_custom_normals:Boolean = true,
			use_ani:Boolean = true,
			anim_offset:Number = 1,
			use_custom_props:Boolean = true,
			use_custom_props_enum_as_string:Boolean = true,
			ignore_leaf_bones:Boolean = false,
			force_connect_children:Boolean = false,
			automatic_bone_orientation:Boolean = false,
			primary_bone_axis:String = "Y",
			secondary_bone_axis:String = "X",
			use_prepost_rot:Boolean = true){
			super(ParserDataFormat.BINARY);
			//this.parse(this._data);
		}
		
			
		
		override arcane function resolveDependency(resourceDependency:ResourceDependency):void
		{
			
		}
		override arcane function resolveDependencyFailure(resourceDependency:ResourceDependency):void
		{
			
		}
		public static function supportsType(extension:String):Boolean
		{
			extension = extension.toLowerCase();
			return extension == "fbx";
		}
		protected override function proceedParsing():Boolean
		{
			return PARSING_DONE;
		}
		protected override function startParsing(frameLimit:Number):void
		{
			this.fbx_table_nodes = [];
			trace("START");
			var elem:FBXElem = this.parse(_data);
			trace("FBX import: Prepare...");
			var fbx_settings:FBXElem = this.elemFindFirst(elem, "GlobalSettings");
			var fbx_settings_props:FBXElem = this.elemFindFirst(fbx_settings, "Properties70");
			
			//trace(fbx_settings_props.elems[7].props);
			
			var unit_scale:Number = this.elemPropGetNumber(fbx_settings_props, "UnitScaleFactor", 1);
			var unit_scale_org:Number = this.elemPropGetNumber(fbx_settings_props, "OriginalUnitScaleFactor", 1);
			var axisForward:Number = this.elemPropGetInt(fbx_settings_props, "FrontAxisSign", 10);
			var axisUp:Number = this.elemPropGetInt(fbx_settings_props, "UpAxis", 10);
			var axisCoord:Number = this.elemPropGetInt(fbx_settings_props, "CoordAxis", 10);		
			
			var custom_fps:Number = this.elemPropGetNumber(fbx_settings_props,"CustomFrameRate", 60);
			var time_mode:int = this.elemPropGetEnum(fbx_settings_props, "TimeMode");
			
			var settings:FBXImportSettings = new FBXImportSettings();
			
			trace("FBX import: Templates...");
			var fbx_defs:FBXElem = this.elemFindFirst(elem, "Definitions");
			var fbx_nodes:FBXElem = this.elemFindFirst(elem, "Objects");
			var fbx_connections:FBXElem = this.elemFindFirst(elem, "Connections");
			if((fbx_nodes == null) || (fbx_connections == null)){
				trace("Error");
			}
			fbx_templates = [];
			if(fbx_defs != null){
				for each(var fbx_def:FBXElem in fbx_defs.elems){
					if(fbx_def.id == "ObjectType"){
						for each(var fbx_subdef:FBXElem in fbx_def.elems){
							if(fbx_subdef.id == "PropertyTemplate"){
								if((fbx_subdef.props_type[0] == "S") && (fbx_def.props_type[0] == "S")){
									var key:String = fbx_def.props[0] + fbx_subdef.props[0];
									//trace(key);
									this.fbx_templates[key] = fbx_subdef;
								}
							}
						}
					}
				}
			}
			trace("FBX import: Nodes...");
			for each(var fbx_obj:FBXElem in fbx_nodes.elems){
				if((fbx_obj.props_type[0] == "L") && (fbx_obj.props_type[1] == "S") && (fbx_obj.props_type[2] == "S")){
					var fbx_uuid:Number = this.elem_uuid(fbx_obj);
					fbx_table_nodes[fbx_uuid] = fbx_obj ? fbx_obj : null;
				}
			}
			trace("FBX import: Connections...");
			var fbx_connections_map1:Dictionary = new Dictionary();
			var fbx_connections_map1_reverse:Dictionary = new Dictionary();
			
			fbx_connections_map = [];
			fbx_connections_map_reverse = [];
			for each(var fbx_link:FBXElem in fbx_connections.elems){
				var c_type:String = String(fbx_link.props[0]);
				if((fbx_link.props_type[1] == "L") && (fbx_link.props_type[2] == "L")){
					var src:Number = fbx_link.props[1] as Number;
					var dst:Number = fbx_link.props[2] as Number;
					
					fbx_connections_map1[src] = new Dictionary();
					fbx_connections_map1[src][dst] = fbx_link;
					fbx_connections_map1_reverse[dst] = new Dictionary();
					fbx_connections_map1_reverse[dst][src] = fbx_link;
					
					
					//fbx_connections_map1[dst] = fbx_link;
					//fbx_connections_map1_reverse[dst] = new Dictionary();
					//fbx_connections_map1_reverse[src] = fbx_link;
					
					this.fbx_connections_map[src] = [];
					this.fbx_connections_map[dst] = fbx_link;
					this.fbx_connections_map_reverse[dst] = [];
					this.fbx_connections_map_reverse[src] = fbx_link;
				}
			}			
			trace("FBX import: Meshes...");		
			this.fbx_item = [];
			var fbx_template:FBXElem = this.fbxTemplateGet("GeometryFbxMesh");
			if(fbx_template != null){
				for(var key:String in this.fbx_table_nodes){
					var fbx_item:FBXElem = this.fbx_table_nodes[key] as FBXElem;
					if(fbx_item.id != "Geometry") continue;
					if(fbx_item.id == "Geometry"){
						if(fbx_item.props[2] == "Mesh"){							
							this.finalizeAsset(this.readGeom(fbx_template, fbx_item, settings));
							this.proceedParsing();
						}
					}
				}
			}
			trace("FBX import: Materials & Textures...");
			var fbx_template:FBXElem = this.fbxTemplateGet("MaterialFbxSurfacePhong");
			for(var key:String in this.fbx_table_nodes){
				var fbx_obj:FBXElem = this.fbx_table_nodes[key];
				if(fbx_obj.id != "Material"){
					continue;
				}
				trace("Read Material");
				this.finalizeAsset(this.readMaterial(fbx_template, fbx_obj, settings));
				this.proceedParsing();
			}
			
			
			
			trace("FBX import: Cameras & Lamps");
			var fbx_template:FBXElem = this.fbxTemplateGet("NodeAttributeFbxCamera");
			for(var key:String in this.fbx_table_nodes){
				var fbx_obj:FBXElem = this.fbx_table_nodes[key];
				if(fbx_obj.id != "NodeAttribute"){
					continue;
				}
				if(fbx_obj.props[2] == "Camera"){
					this.finalizeAsset(this.readCamera(fbx_template, fbx_obj, 1));
					this.proceedParsing();
				}
			}
			
			var fbx_template:FBXElem = this.fbxTemplateGet("NodeAttributeFbxLight");	
			for(var key:String in this.fbx_table_nodes){
				var fbx_obj:FBXElem = this.fbx_table_nodes[key];
				if(fbx_obj.id != "NodeAttribute"){
					continue;
				}
				if(fbx_obj.props[2] == "Light"){
					this.finalizeAsset(this.readLight(fbx_template, fbx_obj, 1));
					this.proceedParsing();
				}
			}
			
			trace("FBX import: Objects & Armatures...");
			this.fbx_helper_nodes = [];
			var root_helper:FBXImportHelperNode = new FBXImportHelperNode(null, null, null, false);
			root_helper.is_root = true;
			this.fbx_helper_nodes[0] = root_helper;
			
			var fbx_template:FBXElem = this.fbxTemplateGet("ModelFbxNode");
			if(fbx_template != null){
				for(var key:String in this.fbx_table_nodes){
					var fbx_item:FBXElem = this.fbx_table_nodes[key] as FBXElem;
					if(fbx_item.id != "Model") continue;
					if(fbx_item.id == "Model"){
						var fbx_props:FBXElem = this.elemFindFirst(fbx_item, "Properties70");
						var transform_data:FBXTransformData = this.readObjectTransformPreProcess(fbx_props, fbx_item, new Matrix3D(), true);
						var is_bone:Boolean = false;
						if((fbx_item.props[2] == "LimbNode") || (fbx_item.props[2] == "Limb")){
							is_bone = true;
						}
						this.fbx_helper_nodes[key] = new FBXImportHelperNode(fbx_item, null, transform_data, is_bone);
					}
				}
			}
			for each(var fbx_link:FBXElem in fbx_connections.elems){
				if(fbx_link.props[0] != "OO"){
					continue;
				}
				if((fbx_link.props_type[1] == "L") && (fbx_link.props_type[2] == "L")){
					var c_src:Number = Number(fbx_link.props[1]);
					var c_dst:Number = Number(fbx_link.props[2]);
					var parent:FBXImportHelperNode = this.fbx_helper_nodes[c_dst];
					if(parent == null){
						continue;
					}
					var child:FBXImportHelperNode = this.fbx_helper_nodes[c_src];
					if(child == null){
						var fbx_sdata:FBXElem = this.fbx_table_nodes[c_src];
						if(fbx_sdata == null){
							continue;
						}
						if((fbx_sdata.id != "Geometry") || (fbx_sdata.id != "NodeAttribute")){
							continue;
						}
						parent.bl_data = fbx_sdata;
					}else{
						child.parent = parent;
					}
				}
			}
			root_helper.find_armatures();
			root_helper.find_bone_children();
			root_helper.find_fake_bones();
			if(settings.ignore_leaf_bones){
				root_helper.mark_leaf_bones();
			}
			for(var key:String in this.fbx_table_nodes){
				var fbx_obj:FBXElem = this.fbx_table_nodes[key];
				if(fbx_obj != null) continue;
				if(fbx_obj.id != "Pose") continue;
				if(fbx_obj.props[2] != "BindPose") continue;
				for each(var fbx_pose_node:FBXElem in fbx_obj.elems){
					if(fbx_pose_node.id != "PoseNode") continue;
					
					var node_elem:FBXElem = this.elemFindFirst(fbx_pose_node, "Node");
					var node:Number = this.elem_uuid(node_elem);
					var matrix_elem:FBXElem = this.elemFindFirst(fbx_pose_node, "Matrix");
					var matrix:Matrix3D;
					var bone:FBXImportHelperNode = this.fbx_helper_nodes[node];
					if((bone != null) && (matrix != null)){
						bone.bind_matrix = matrix;
					}
				}
			}
			for(var helper_uuid:String in this.fbx_helper_nodes){
				var helper_node:FBXImportHelperNode = this.fbx_helper_nodes[helper_uuid];
				if(!helper_node.is_bone) continue;
				for(var cluster_uuid:String in fbx_connections_map1[helper_uuid]){
					var cluster_link:FBXElem = fbx_connections_map1[helper_uuid][cluster_uuid];
					if(cluster_link.props[0] != "OO"){
						continue;
					}
					var fbx_cluster:FBXElem = this.fbx_table_nodes[cluster_uuid];
					if((fbx_cluster != null) && (fbx_cluster.id != "Deformer") || (fbx_cluster != null) && (fbx_cluster.props[2] != "Cluster")){
						continue;
					}
					var tx_mesh_elem:FBXElem = this.elemFindFirst(fbx_cluster, "Transform", null);
					var tx_mesh:Matrix3D = this.array_to_matrix4(String(tx_mesh_elem.props[0]), new Matrix3D());
					var tx_bone_elem:FBXElem = this.elemFindFirst(fbx_cluster, "TransformLink", null);
					var tx_bone:Matrix3D = this.array_to_matrix4(String(tx_bone_elem.props[0]), null);
					var tx_arm_elem:FBXElem = this.elemFindFirst(fbx_cluster, "TransformAssociateModel", null);
					var tx_arm:Matrix3D = null;					
					if(tx_arm_elem != null){
						tx_arm = this.array_to_matrix4(String(tx_arm_elem.props[0]), null);
					}				
					var mesh_matrix:Matrix3D = tx_mesh;
					var armature_matrix:Matrix3D = tx_arm;
					if(tx_bone != null){
						mesh_matrix = tx_bone;
						helper_node.bind_matrix = tx_bone;
					}
					var meshes:Vector.<FBXImportHelperNode> = new Vector.<FBXImportHelperNode>;
					for(var skin_uuid:String in fbx_connections_map1[cluster_uuid]){
						var skin_link:FBXElem = fbx_connections_map1[cluster_uuid][skin_uuid];
						if(skin_link.props[0] != "OO"){
							continue;
						}
						var fbx_skin:FBXElem = this.fbx_table_nodes[skin_uuid];
						if((fbx_skin != null) && (fbx_skin.id != "Deformer") || (fbx_skin != null) && (fbx_skin.props[2] != "Skin")){
							continue;
						}
						for(var mesh_uuid:String in fbx_connections_map1[skin_uuid]){
							var mesh_link:FBXElem = fbx_connections_map1[skin_uuid][mesh_uuid];
							if(mesh_link.props[0] != "OO"){
								continue;
							}
							var fbx_mesh:FBXElem = this.fbx_table_nodes[mesh_uuid];
							if((fbx_mesh != null) && (fbx_mesh.id != "Geometry") || (fbx_mesh != null) && (fbx_mesh.props[2] != "Mesh")){
								continue;
							}
							for(var object_uuid:String in fbx_connections_map1[mesh_uuid]){
								var object_link:FBXElem = fbx_connections_map1[mesh_uuid][object_uuid];
								if(object_link.props[0] != "OO"){
									continue;
								}
								var mesh_node:FBXImportHelperNode = this.fbx_helper_nodes[object_uuid];
								if(mesh_node != null){
									mesh_node.armature_setup[helper_node.armature] = mesh_matrix;
									meshes.push(mesh_node);
								}
							}							
						}
					}
					helper_node.clusters.push([fbx_cluster, meshes]);
				}
			}
			root_helper.make_bind_pose_local();
			root_helper.collect_armature_meshes();
			root_helper.find_correction_matrix(settings);
			root_helper.build_hierarchy(fbx_template, settings, null);
			root_helper.link_hierarchy(fbx_template, settings, null);
			
			trace("FBX import: ShapeKeys...");
			
			trace("FBX import: Animations...");
			var fbx_template_astack:FBXElem = this.fbxTemplateGet("AnimationStackFbxAnimStack");
			var fbx_template_alayer:FBXElem = this.fbxTemplateGet("AnimationLayerFbxAnimLayer");
			var stacks:Array = [];
			for(var key:String in this.fbx_table_nodes){
				var fbx_asdata:FBXElem = this.fbx_table_nodes[key];
				if((fbx_asdata.id != "AnimationStack") || (fbx_asdata.props[2] != "")){
					continue;
				}
				stacks[key] = fbx_asdata;
				trace(fbx_asdata.id);
			}
			
			trace("FBX import: Assign Materials...");
			for(var key:String in this.fbx_table_nodes){
				var fbx_obj:FBXElem = this.fbx_table_nodes[key];
				if(fbx_obj.id != "Geometry"){
					continue;
				}
				var mesh:FBXElem = this.fbx_table_nodes[key];
				if(mesh == null){
					continue;
				}
				
			}
			
			trace("FBX import: Assign Textures...");
			
			trace("FBX import: Finished...");
			
		}
		
		private function array_to_matrix4(indata:String, def:*):Matrix3D{
			var data:Vector.<Number> = new Vector.<Number>;
			var temp:Array = indata.split(",");
			for(var i:int = 0; i < temp.length; i++){
				data.push(Number(temp[i]));
			}
			if(data.length == 16){
				var mat:Matrix3D = new Matrix3D(data);
				return mat;
			}else{
				return def;
			}
		}
		private function fbxTemplateGet(key:String):FBXElem{
			return this.fbx_templates[key];
		}
		private function parse(buffer:ByteArray):FBXElem{
			buffer.endian = Endian.LITTLE_ENDIAN;
			var root_elems:Vector.<FBXElem> = new Vector.<FBXElem>;
			var header:String = buffer.readUTFBytes(20);
			if(header.indexOf("Kaydara FBX Binary") == -1){
				throw new Error("Invalid Header");
			}
			buffer.position = 23;
			var fbx_version:int = this.read_uint(buffer);
			if(fbx_version != 7400)	throw new Error("Only Version 7.4 is supported");
			while(true){
				var elem:FBXElem = this.read_elem(buffer, buffer.position);
				if(elem == null){
					break;
				}
				root_elems.push(elem);
			}
			return new FBXElem("", null, null, root_elems);
		}
		private function elem_uuid(elem:FBXElem):Number{
			return Number(elem.props[0]);
		}
		private function read_elem(buffer:ByteArray, position:int):FBXElem{
			var end_offset:int = read_uint(buffer);
			if(end_offset == 0) return null;
			var prop_count:int = this.read_uint(buffer);
			var prop_length:int= this.read_uint(buffer);
			var elem_id:String = this.read_string_ubyte(buffer);
			var elem_props_type:Vector.<String> = new Vector.<String>(prop_count);
			var elem_props_data:Vector.<Object> = new Vector.<Object>(prop_count);			
			
			var elem_subtree:Vector.<FBXElem> = new Vector.<FBXElem>;			
			for(var i:int = 0; i < prop_count; i++){
				var dataType:String = buffer.readUTFBytes(1);
				elem_props_data[i] = this.read_data(buffer, dataType);
				elem_props_type[i] = dataType;
			}
			if(buffer.position < end_offset){
				while(buffer.position < (end_offset - 13)){
					elem_subtree.push(this.read_elem(buffer, buffer.position));
				}
				if(buffer.readByte() != 0 || buffer.readByte() != 0 || buffer.readByte() != 0 || buffer.readByte() != 0 || buffer.readByte() != 0 || buffer.readByte() != 0 || buffer.readByte() != 0 || buffer.readByte() != 0 || buffer.readByte() != 0 || buffer.readByte() != 0 || buffer.readByte() != 0 || buffer.readByte() != 0 || buffer.readByte() != 0){
					throw new Error("failed to read nested block sentinel, expected all bytes to be 0");
				}
			}
			if(buffer.position != end_offset){
				throw new Error("scope length not reached, something is wrong");
			}
			return new FBXElem(elem_id, elem_props_data, elem_props_type, elem_subtree);
		}
		private function read_data(buffer:ByteArray, dataType:String):Object{
			var len:int;
			switch(dataType){
				case "Y":	return buffer.readShort();	break;
				case "C":	return buffer.readByte();	break;
				case "I":	return buffer.readInt();	break;
				case "F":	return buffer.readFloat();	break;
				case "D":	return buffer.readDouble();	break;
				case "L":	return buffer.readDouble();	break;
				case "R":	len = buffer.readInt();	var data:ByteArray = new ByteArray();	buffer.readBytes(data, 0, len);	return data;	break;
				case "S":	len = buffer.readInt();	return buffer.readUTFBytes(len);		break;
				case "f":	return this.unpack_array(buffer, dataType, 4, Endian.LITTLE_ENDIAN);	break;
				case "i":	return this.unpack_array(buffer, dataType, 4, Endian.LITTLE_ENDIAN);	break;
				case "d":	return this.unpack_array(buffer, dataType, 8, Endian.LITTLE_ENDIAN);	break;
				case "l":	return this.unpack_array(buffer, dataType, 8, Endian.LITTLE_ENDIAN);	break;
				case "b":	return this.unpack_array(buffer, dataType, 1, Endian.LITTLE_ENDIAN);	break;
				case "c":	return this.unpack_array(buffer, dataType, 2, Endian.LITTLE_ENDIAN);	break;
			}
			return null;
		}
		public function read_uint(buffer:ByteArray):int{
			return buffer.readUnsignedInt();
		}
		public function read_ubyte(buffer:ByteArray):int{
			return buffer.readUnsignedByte();
		}
		public function read_string_ubyte(buffer:ByteArray):String{
			var size:int = this.read_ubyte(buffer);
			return buffer.readUTFBytes(size);
		}
		public function unpack_array(buffer:ByteArray, array_type:String, array_stride:int, array_byteswap:String = "littleEndian"):*{
			var length:int = this.read_uint(buffer);
			var encoding:int = this.read_uint(buffer);
			var comp_len:int = this.read_uint(buffer);
			var data:ByteArray = new ByteArray();
			data.endian = array_byteswap;
			buffer.readBytes(data,0,comp_len);
			if(encoding == 1) data.uncompress();
			var i:int;
			switch(array_type){
				case "f":	var v1:Vector.<Number> = new Vector.<Number>;	for(i = 0; i < length; i++) v1.push(data.readFloat());	return v1;
					break;
				case "i":	var v2:Vector.<int> = new Vector.<int>;			for(i = 0; i < length; i++) v2.push(data.readInt());	return v2;
					break;
				case "d":	var v3:Vector.<Number> = new Vector.<Number>;	for(i = 0; i < length; i++) v3.push(data.readDouble());	return v3;
					break;
				case "l":	var v4:Vector.<Number> = new Vector.<Number>;	for(i = 0; i < length; i++) v4.push(data.readDouble());	return v4;
					break;
				case "b":	var v5:Vector.<Number> = new Vector.<Number>;	for(i = 0; i < length; i++) v5.push(data.readByte());	return v5;
					break;
				case "c":	var v6:Vector.<Number> = new Vector.<Number>;	for(i = 0; i < length; i++) v6.push(data.readByte());	return v6;
					break;
			}
			return null;
		}
		
		private function elemFindFirst(elem:FBXElem, idSearch:String, def:FBXElem = null):FBXElem{
			if((elem != null) && (elem.elems != null)){
				for each(var fbx:FBXElem in elem.elems){
					if(fbx.id == idSearch){
						return fbx;
					}
				}
			}
			return def;
		}
		private function elemFindFirstString(elem:FBXElem, idSearch:String):String{
			var fbxItem:FBXElem = this.elemFindFirst(elem, idSearch);
			if((fbxItem != null) && (fbxItem.props != null) && (fbxItem.props.length == 1) && (fbxItem.props_type[0] == "S")){
				return String(fbxItem.props[0]);
			}
			return null;
		}
		private function elemPropsFindFirst(elemPropId:String,... elem):*{
			if(elem == null)	return null;
			for(var i:int = 0; i < elem.length; i++){				
				var r:FBXElem = elem[i];
				if(r.id != "P"){
					for each(var sub:FBXElem in r.elems){
						if(sub.id == "P"){
							if(sub.props[0] == elemPropId){
								return sub;
							}
						}			
					}
				}else{
					return r;
				}
			}
			return null;
		}
		private function elemPropsGetColorRGB(elem:FBXElem, elemPropId:String, def:uint = 0xffffff):uint{
			var elemProp:FBXElem = this.elemPropsFindFirst(elemPropId, [elem]);
			if(elemProp != null){
				if(elemProp.props[0] == elemPropId){
					if((elemProp.props[1] == "Color") && (elemProp.props[2] == "") || (elemProp.props[1] == "ColorRGB") && (elemProp.props[2] == "Color")){
						return this.combineRGB(uint(elemProp.props[4]), uint(elemProp.props[5]), uint(elemProp.props[6]));
					}
				}
			}			
			return def;
		}
		private function elemPropGetVector3D(elem:FBXElem, elemPropId:String, def:Vector3D = null):Vector3D{
			var v:Vector3D = new Vector3D();
			var elemProp:FBXElem = this.elemPropsFindFirst(elemPropId, elem);
			if(((elemProp != null) && (elemProp.props_type[4] == "F") && (elemProp.props_type[5] == "F") && (elemProp.props_type[6] == "F")) || ((elemProp != null) && (elemProp.props_type[4] == "D") && (elemProp.props_type[5] == "D") && (elemProp.props_type[6] == "D"))){
				return new Vector3D(Number(elemProp.props[4]),Number(elemProp.props[5]),Number(elemProp.props[6]));
			}			
			return v;
		}
		private function elemPropGetNumber(elem:FBXElem, elemPropId:String, def:Number):Number{
			
			var elemProp:FBXElem = this.elemPropsFindFirst(elemPropId, elem);			
			if((elemProp != null) && (elemProp.props[0] == elemPropId) && (elemProp.props[1] == "double") && (elemProp.props[2] == "Number") || (elemProp != null) && (elemProp.props[0] == elemPropId) && (elemProp.props[1] == "Number") && (elemProp.props[2] == "")){
				return Number(elemProp.props[4]);
			}			
			return def;
		}
		private function elemPropGetInt(elem:FBXElem, elemPropId:String, def:int):int{
			var elemProp:FBXElem = this.elemPropsFindFirst(elemPropId, elem);			
			
			if((elemProp != null) && (elemProp.props[0] == elemPropId) && (elemProp.props[1] == "int") && (elemProp.props[2] == "Integer") || (elemProp != null) && (elemProp.props[0] == elemPropId) && (elemProp.props[1] == "ULongLong") && (elemProp.props[2] == "")){
				return int(elemProp.props[4]);
			}			
			return def;
		}
		private function elemPropGetBool(elem:FBXElem, elemPropId:String, def:Boolean):Boolean{
			var elemProp:FBXElem = this.elemPropsFindFirst(elemPropId, elem);		
			if((elemProp != null) && (elemProp.props[0] == elemPropId) && (elemProp.props[1] == "bool") && (elemProp.props[2] == "") && (elemProp.props[3] == "")){
				return Boolean(elemProp.props[4]);
			}			
			return def;
		}
		private function elemPropGetEnum(elem:FBXElem, elemPropId:String, def:int = -1):int{
			var elemProp:FBXElem = this.elemPropsFindFirst(elemPropId, elem);
			if((elemProp != null) && (elemProp.props[0] == elemPropId) && (elemProp.props[1] == "enum") && (elemProp.props[2] == "") && (elemProp.props[3] == "")){
				return int(elemProp.props[4]);
			}
			return def;
		}
		private function elemPropGetVisibility(elem:FBXElem, elemPropId:String, def:Number):Number{
			var elemProp:FBXElem = this.elemPropsFindFirst(elemPropId, elem);		
			if((elemProp != null) && (elemProp.props[0] == elemPropId) && (elemProp.props[1] == "Visibility") && (elemProp.props[2] == "")){
				return Number(elemProp.props[4]);
			}			
			return def;
		}
		
		private function combineRGB(r:uint, g:uint, b:uint):uint{
			return ((r << 16) | (g << 8) | b);
		}
		
		
		private function readCustomProperties(fbxObj:FBXElem, settings:FBXImportSettings):void{
			
			
		}
		private function readObjectTransformDo(transformData:FBXTransformData):void{}
		private function addVGroupToObjects():void{}
		private function readObjectTransformPreProcess(fbx_props:FBXElem, fbx_obj:FBXElem, rot_alt_mat:Matrix3D, use_prepost_rot:Boolean):FBXTransformData{
			var const_vector3D_Zero:Vector3D = new Vector3D();
			var const_vector3D_One:Vector3D = new Vector3D(1,1,1);

			var loc:Vector3D = this.elemPropGetVector3D(fbx_props, "Lcl Translation", const_vector3D_Zero);
			var rot:Vector3D = this.elemPropGetVector3D(fbx_props, "Lcl Rotation", const_vector3D_Zero);
			var sca:Vector3D = this.elemPropGetVector3D(fbx_props, "Lcl Scaling", const_vector3D_One);
			
			var geom_loc:Vector3D = this.elemPropGetVector3D(fbx_props, "GeometricTranslation", const_vector3D_Zero);
			var geom_rot:Vector3D = this.elemPropGetVector3D(fbx_props, "GeometricRotation", const_vector3D_Zero);
			var geom_sca:Vector3D = this.elemPropGetVector3D(fbx_props, "GeometricScaling", const_vector3D_One);
			
			var rot_ofs:Vector3D = this.elemPropGetVector3D(fbx_props, "RotationOffset", const_vector3D_Zero);
			var rot_piv:Vector3D = this.elemPropGetVector3D(fbx_props, "RotationPivot", const_vector3D_Zero);
			var sca_ofs:Vector3D = this.elemPropGetVector3D(fbx_props, "ScalingOffset", const_vector3D_Zero);
			var sca_piv:Vector3D = this.elemPropGetVector3D(fbx_props, "ScalingPivot", const_vector3D_Zero);
			
			var is_rot_act:Boolean = this.elemPropGetBool(fbx_props, "RotationActive", false);
			
			var pre_rot:Vector3D;
			var pst_rot:Vector3D;
			var rot_ord:String = "XYZ";
			
			if(is_rot_act){
				if(use_prepost_rot){
					pre_rot = this.elemPropGetVector3D(fbx_props, "PreRotation", const_vector3D_Zero);
					pst_rot = this.elemPropGetVector3D(fbx_props, "PostRotation", const_vector3D_Zero);
				}else{
					pre_rot = const_vector3D_Zero;
					pst_rot = const_vector3D_Zero;
				}
				switch(this.elemPropGetEnum(fbx_props, "RotationOrder", 0)){
					default:
					case 0:	rot_ord = "XYZ";	break;
					case 1:	rot_ord = "XZY";	break;
					case 2:	rot_ord = "YZX";	break;
					case 3:	rot_ord = "YXZ";	break;
					case 4:	rot_ord = "ZXY";	break;
					case 5:	rot_ord = "ZYX";	break;
					case 6:	rot_ord = "XYZ";	break;
				}				
			}else{
				pre_rot = const_vector3D_Zero;
				pst_rot = const_vector3D_Zero;
			}
			return new FBXTransformData(loc, geom_loc, rot, rot_ofs, rot_piv, pre_rot, pst_rot, rot_ord, rot_alt_mat, geom_rot, sca, sca_ofs, sca_piv, geom_sca);
		}
		
		private function readAnimationsCurvesIter():void{}
		private function readAnimationsActionItem():void{}
		private function readAnimations():void{}
		private function readGeomLayerInfo(fbx_layer:FBXElem):Array{
			return [this.elemFindFirstString(fbx_layer, "Name"), this.elemFindFirstString(fbx_layer, "MappingInformationType"), this.elemFindFirstString(fbx_layer, "ReferenceInformationType")];
		}
		private function readGeomArraySetAttr():void{}
		private function readGeomArrayGenAllSame():void{}
		private function readGeomArrayGenDirect():void{}
		private function readGeomArrayGenIndexToDirect():void{}
		private function readGeomArrayGenDirectLooptOvert():void{}
		private function readGeomArrayErrorMapping():void{}
		private function readGeomArrayErrorRef():void{}
		private function readGeomArrayMappedVert():void{}
		private function readGeomArrayMappedEdge():void{}
		private function readGeomArrayMappedPolygon():void{}
		private function readGeomArrayMappedPolyLoop():void{}
		private function readGeomLayerMaterial():void{}
		private function readGeomLayerUV(fbx_obj:FBXElem, mesh:Mesh):void{
			var elem:FBXElem = this.elemFindFirst(fbx_obj, "LayerElementUV");
			//trace(elem);
		}
		private function readGeomLayerColor():void{}
		private function readGeomLayerSmooth():void{}
		private function readGeomLayerNormal(fbx_obj:FBXElem, mesh:Mesh):void{
			var fbx_layer:FBXElem = this.elemFindFirst(fbx_obj, "LayerElementNormal");
			if(fbx_layer == null){
				return;
			}
			var fbx_layerInfo:Array = this.readGeomLayerInfo(fbx_layer);
			var layer_id:String = "Normals";
			var fbx_layer_data:FBXElem = this.elemFindFirst(fbx_layer, layer_id);
			var fbx_layer_index:FBXElem = this.elemFindFirst(fbx_layer, "NormalsIndex");			
			if(fbx_layer_data != null){
				var sub:SubGeometry = mesh.geometry.subGeometries[0] as SubGeometry;
				var normals:Vector.<Number> = this.stringToVectorNormals(String(fbx_layer_data.props));
				//trace(normals.length);				
				//sub.updateVertexNormalData(normals);
			}
		}
		private function readGeom(fbx_template:FBXElem, fbx_obj:FBXElem, settings:FBXImportSettings):Mesh{
			var fbx_verts:FBXElem = this.elemFindFirst(fbx_obj, "Vertices");
			var fbx_polys:FBXElem = this.elemFindFirst(fbx_obj, "PolygonVertexIndex");
			var fbx_edges:FBXElem = this.elemFindFirst(fbx_obj, "Edges");
			
			var subgeometry:SubGeometry = new SubGeometry();
			subgeometry.updateVertexData(this.stringToVectorNumber(String(fbx_verts.props)));
			subgeometry.updateIndexData(this.stringToIndex(String(fbx_polys.props)));
			subgeometry.autoGenerateDummyUVs = true;
			subgeometry.autoDeriveVertexNormals = true;
			
			var geometry:Geometry = new Geometry();
			geometry.addSubGeometry(subgeometry);
			var mesh:Mesh = new Mesh(geometry);
			mesh.name = String(fbx_obj.props[1]);
			
			
			if(fbx_polys != null){
				//this.readGeomLayerUV(fbx_obj, mesh);
				//this.readGeomLayerNormal(fbx_obj, mesh);
			}
			
			return mesh;
		}
		private function readShape():void{}
		private function readMaterial(fbx_template:FBXElem, fbx_obj:FBXElem, settings:FBXImportSettings):MaterialBase{
			var ma:MaterialBase = new MaterialBase();
			var consts_color_white:uint = 0xffffff;
			var fbx_props:FBXElem = this.elemFindFirst(fbx_template, "Properties70");
			trace(fbx_props.props);
			return ma;
		}
		private function readTextureImage():void{}
		private function readCamera(fbx_template:FBXElem, fbx_obj:FBXElem, scale:Number):Camera3D{
			var fbx_props:FBXElem = this.elemFindFirst(fbx_obj, "Properties70");
			var position:Vector3D 	= new Vector3D(Number(fbx_props.elems[0].props[4]), Number(fbx_props.elems[0].props[5]), Number(fbx_props.elems[0].props[6]));
			var upVector:Vector3D 	= new Vector3D(Number(fbx_props.elems[1].props[4]), Number(fbx_props.elems[1].props[5]), Number(fbx_props.elems[1].props[6]));
			var lookAt:Vector3D 	= new Vector3D(Number(fbx_props.elems[2].props[4]), Number(fbx_props.elems[2].props[5]), Number(fbx_props.elems[2].props[6]));
			var near:Number 		= Number(fbx_props.elems[21].props[4]);;
			var far:Number 			= Number(fbx_props.elems[22].props[4]);
			var camera:Camera3D = new Camera3D();
			camera.position = position;
			camera.lookAt(lookAt, upVector);	
			camera.lens.near = near;
			camera.lens.far = far;
			return camera;
		}
		private function readLight(fbx_template:FBXElem, fbx_obj:FBXElem, scale:Number):LightBase{
			var lamp:LightBase = null;
			var fbx_props:FBXElem  = this.elemFindFirst(fbx_obj, "Properties70");
			var fbx_props1:FBXElem = this.elemFindFirst(fbx_template, "Properties70", null);
			switch(int(fbx_props.elems[0].props[4])){
				default:
				case 0:	lamp = new PointLight();	break;
				case 1:	lamp = new DirectionalLight();break;
				case 2:	trace("Spot Lights Are Not Yet Supported");break;
			}
			lamp.castsShadows = Boolean(fbx_props.elems[1].props[4]);
			var colorR:uint = uint(Math.round(uint(fbx_props.elems[2].props[4]) * 255));
			var colorG:uint = uint(Math.round(uint(fbx_props.elems[2].props[5]) * 255));
			var colorB:uint = uint(Math.round(uint(fbx_props.elems[2].props[6]) * 255));			
			lamp.color = this.combineRGB(colorR, colorG, colorB);
			//intensity = fbx_props.elems[3].props
			return lamp;
		}
		
		private function stringToIndex(instr:String):Vector.<uint>{
			var data:Array = instr.split(",");
			var ret:Vector.<uint> = new Vector.<uint>;
			for(var i:int = 0; i < data.length; i += 3){
				ret.push(uint(data[i]));
				ret.push(uint(data[i+1]));
				ret.push(uint(data[i+2] ^= -1));
			}
			return ret;
		}
		private function stringToVectorNormals(instr:String):Vector.<Number>{
			var data:Array = instr.split(",");
			//trace("Total Normals " + data);
			var ret:Vector.<Number> = new Vector.<Number>;
			for(var i:int = 0; i < data.length; i += 36){
				ret.push(Number(data[i+0]));
				ret.push(Number(data[i+1]));
				ret.push(~Number(data[i+2]));
			}
			return ret;
		}
		private function stringToVectorNumber(instr:String):Vector.<Number>{
			var data:Array = instr.split(",");
			//trace("Total Verts" + data.length);
			var ret:Vector.<Number> = new Vector.<Number>;
			for(var i:int = 0; i < data.length; i++){
				ret.push(Number(data[i]));
			}
			
			return ret;
		}
	}
}

import flash.geom.Matrix;
import flash.geom.Matrix3D;
import flash.geom.Vector3D;

import away3d.animators.data.Skeleton;
import away3d.animators.utils.SkeletonUtils;
import away3d.containers.Scene3D;


internal class FBXUtils{
	public function FBXUtils(){
		
	}
	public static function units_convertor(from:Number, to:Number):Number{
		return to / from;
	}
	public static function matrix4ToArray(mat:Matrix3D):Vector.<Number>{
		return mat.rawData;
	}
	public static function similarValues(v1:Number, v2:Number, e:Number=1e-6):Boolean{
		if(v1 == v2) return true;
		return ((Math.abs(v1 - v2) / Math.max(Math.abs(v1), Math.abs(v2))) <= e);
	}
	public static function similarValuesInt(v1:int, v2:int, e:Number=1e-6):Boolean{
		if(v1 == v2) return true;
		return ((Math.abs(v1 - v2) / Math.max(Math.abs(v1), Math.abs(v2))) <= e);
	}
	public static function keyToUUID(uuids:Vector.<Number>, key:Number):Number{
		var uuid:int;
		if(key is int){
			uuid = key;
		}else{
			uuid = key;
			if(uuid < 0) uuid = -uuid;
			if(uuid >= 2*63) uuid /=2;
		}
		if(uuid > 1e9){
			var t_uuid:Number = uuid % 1e9;
			
		}	
		return uuid;
	}
}
internal class FBXElem{
	public var id:String;
	public var props:Vector.<Object>;
	public var props_type:Vector.<String>;
	public var elems:Vector.<FBXElem>;
	public var _props_length:int;
	public var _end_offset:int;
	public function FBXElem(id:String, props:Vector.<Object>, props_type:Vector.<String>, elems:Vector.<FBXElem>, props_length:int = -1, end_offset:int = -1){
		this.id = id;
		this.props = props;
		this.props_type = props_type;
		this.elems = elems;
		this._props_length = props_length;
		this._end_offset = end_offset;
	}
}
internal class FBXImportHelperNode{
	public var fbx_name:String;
	public var fbx_type:String;
	public var fbx_elem:FBXElem;
	public var bl_obj:*;
	public var bl_data:*;
	public var bl_bone:*;
	public var fbx_transform_data:FBXTransformData;
	public var is_root:Boolean;
	public var is_bone:Boolean;
	public var armature:FBXImportHelperNode;
	public var is_armature:Boolean;
	public var has_bone_children:Boolean;
	public var is_leaf:Boolean;
	public var pre_matrix:Matrix3D;
	public var bind_matrix:Matrix3D;
	public var post_matrix:Matrix3D;
	public var bone_child_matrix:Matrix3D;
	public var bone_compensation_matrix:Matrix3D;
	public var meshes:Array;
	public var clusters:Array;
	public var armature_setup:Array;
	public var parent:FBXImportHelperNode;
	public var children:Array;
	public var anim_compensation_matrix:Matrix3D;
	public var matrix:Matrix3D = new Matrix3D();
	public var matrix_as_parent:Matrix3D;
	public var matrix_geom:Matrix3D;
	public function FBXImportHelperNode(fbx_obj:FBXElem, bl_data:*, transform_data:FBXTransformData, isBone:Boolean){	
		if(fbx_obj != null){
			this.fbx_type = fbx_obj.props[2] ? String(fbx_obj.props[2]) : null;
		}
		this.fbx_elem = fbx_elem;
		this.bl_obj = null;
		this.bl_data = bl_data;
		this.bl_bone = null;
		this.fbx_transform_data = transform_data;
		this.is_root = false;
		this.is_bone = isBone;
		this.is_armature = false;
		this.armature = null;
		this.has_bone_children = false;
		this.is_leaf = false;
		this.pre_matrix = null;
		this.bind_matrix = null;
		this.post_matrix = null;
		this.bone_child_matrix = null;
		this.bone_compensation_matrix = null;
		this.meshes = [];
		this.clusters = [];
		this.armature_setup = [];
		this.parent = null;
		this.children = [];
	}
	public function setParent(value:FBXImportHelperNode):void{
		this.parent = value;
	}
	public function print_info(indent:int = 0):void{
		
	}
	public function mark_leaf_bones():void{
		if(this.is_bone && this.children.length == 1){
			var child:FBXImportHelperNode = this.children[0];
			if((child.is_bone) && (child.children.length == 0)){
				child.is_leaf = true;
			}
			for(var key:String in this.children){
				this.children[key].mark_leaf_bones();
			}
		}
	}
	public function do_bake_transform(settings:FBXImportSettings):Boolean{
		return (((settings.bake_space_transform) && (this.fbx_type == "Mesh") || (this.fbx_type == "Null")) && (!this.is_armature) && (!this.is_bone));
	}
	public function find_correction_matrix(settings:FBXImportSettings, parent_correction_inv:Matrix3D = null):void{
		if(((parent != null) && (parent.is_root)) || (parent != null) && (parent.do_bake_transform(settings))){
			this.pre_matrix = settings.global_matrix;
		}
		if(parent_correction_inv){
			if(this.pre_matrix == null){
				this.pre_matrix = new Matrix3D();
			}
		}
		
		if(this.is_bone){
			if(settings.automatic_bone_orientation){
				
			}
		}
	}
	public function find_armature_bones(armature:FBXImportHelperNode):void{
		for(var key:String in children){
			var child:FBXImportHelperNode = this.children[key];
			if(child.is_bone){
				child.armature = armature;
				child.find_armature_bones(armature);
			}
		}
	}
	public function find_armatures():void{
		var needs_armature:Boolean = false;
		for(var key:String in this.children){
			var child:FBXImportHelperNode = this.children[key];
			if(child.is_bone){
				needs_armature = true;
				break;
			}
		}
		if(needs_armature){
			if((this.fbx_type == "Root") || (this.fbx_type == "Null")){
				this.is_armature = true;
				this.armature = this;
			}else{
				this.armature = new FBXImportHelperNode(null, null, null, false);
				this.armature.fbx_name = "Armature";
				this.armature.is_armature = true;
				for(var k2:String in this.children){
					var child2:FBXImportHelperNode = this.children[k2];
					if(child2.is_bone){
						child2.parent = armature;
					}
				}
				armature.parent = this;
			}
			armature.find_armature_bones(armature);
		}
		for(var key:String in this.children){
			var child:FBXImportHelperNode = this.children[key];
			if((child.is_armature) || (child.is_bone)){
				continue;
			}
			child.find_armatures();
		}
	}
	public function find_bone_children():Boolean{
		var has_bone_children:Boolean = false;
		for(var key:String in this.children){
			var child:FBXImportHelperNode = this.children[key];
			has_bone_children = child.find_bone_children();
		}
		this.has_bone_children = has_bone_children;
		return (this.is_bone) || (has_bone_children);
	}
	public function find_fake_bones(in_armature:Boolean = false):void{
		if((in_armature) && (!this.is_bone) && (this.has_bone_children)){
			this.is_bone = true;
		}
		if((this.fbx_type != "Root") || (this.fbx_type != "Null")){
			var node:FBXImportHelperNode = new FBXImportHelperNode(this.fbx_elem, this.bl_data, null, false);
			this.fbx_elem = null;
			this.bl_data = null;
			for(var key:String in this.children){
				var child:FBXImportHelperNode = this.children[key];
				if((child.is_bone) || (child.has_bone_children)){
					continue;
				}
				child.parent = node;
			}
			node.parent = this;
		}
		if(this.is_armature){
			in_armature = true;
		}
		for(var key:String in this.children){
			var child:FBXImportHelperNode = this.children[key];
			child.find_fake_bones(in_armature);
		}
	}
	public function get_world_matrix_as_parent():Matrix3D{
		var matrix:Matrix3D = new Matrix3D();
		if(this.parent != null){
			matrix = this.parent.get_world_matrix_as_parent();
		}
		if(this.matrix_as_parent){
			matrix = this.matrix_as_parent;
		}
		return matrix;
	}
	public function get_world_matrix():Matrix3D{
		var matrix:Matrix3D = new Matrix3D();
		if(this.parent != null){
			matrix = this.parent.get_world_matrix_as_parent();
		}
		if(this.matrix_as_parent){
			matrix = this.matrix_as_parent;
		}
		return matrix;
	}
	public function get_matrix():Matrix3D{
		var matrix:Matrix3D = new Matrix3D();
		if(this.matrix != null){
			matrix = this.matrix;
		}
		if(this.pre_matrix != null){
			matrix.append(this.pre_matrix);
		}
		if(this.post_matrix != null){
			var temp:Matrix3D = this.post_matrix.clone();
			temp.append(matrix);
			matrix = temp;
		}
		return matrix;
	}
	public function get_bind_matrix():Matrix3D{
		var matrix:Matrix3D = new Matrix3D();
		if(this.bind_matrix != null){
			matrix = this.bind_matrix;
		}
		if(this.pre_matrix != null){
			matrix.append(this.pre_matrix);
		}
		if(this.post_matrix != null){
			var temp:Matrix3D = this.post_matrix.clone();
			temp.append(matrix);
			matrix = temp;
		}
		return matrix;
	}
	public function make_bind_pose_local(parent_matrix:Matrix3D = null):void{
		if(parent_matrix == null){
			parent_matrix = new Matrix3D();
		}
		var bind_matrix:Matrix3D=  new Matrix3D();
		if(this.bind_matrix != null){
			bind_matrix = parent_matrix.clone();
			bind_matrix.invert();
			bind_matrix.append(this.bind_matrix);
		}else{
			bind_matrix = this.matrix.clone();
		}
		this.bind_matrix = bind_matrix;
		if(bind_matrix){
			var temp:Matrix3D = parent_matrix;
			temp.append(bind_matrix);
			parent_matrix = temp;
		}
		for(var i:int = 0; i < this.children.length; i++){
			var child:FBXImportHelperNode = this.children[i];
			child.make_bind_pose_local(parent_matrix);
		}
	}
	public function collect_skeleton_meshes(meshes:Array):void{
		for(var i:int = 0; i < clusters.length; i++){
			meshes.push(clusters[i]);
		}
		for(var i:int = 0; i < this.children.length; i++){
			var child:FBXImportHelperNode = this.children[i];
			child.collect_skeleton_meshes(meshes);
		}
	}
	public function collect_armature_meshes():void{
		if(this.is_armature){
			var armature_matrix_inv:Matrix3D = this.get_world_matrix();
			armature_matrix_inv.invert();
			var meshes:Array = new Array();
			for(var i:int = 0; i < this.children.length; i++){
				var child:FBXImportHelperNode = this.children[i];
				child.collect_skeleton_meshes(meshes);
			}
			for(var i:int = 0; i < meshes.length; i++){
				var m:FBXImportHelperNode = meshes[i];
				var old_matrix:Matrix3D = m.matrix;
				m.matrix = armature_matrix_inv;
				m.matrix.append(m.get_world_matrix());
				m.anim_compensation_matrix = old_matrix;
				m.anim_compensation_matrix.invert();
				m.anim_compensation_matrix.append(m.matrix);
				m.parent = this;
			}
			this.meshes = meshes;			
		}else{
			for(var i:int = 0; i < this.children.length; i++){
				var child:FBXImportHelperNode = this.children[i];
				child.collect_armature_meshes();
			}
		}
	}
	public function build_skeleton():void{
		trace("build_skeleton");
	}
	public function build_node_obj(fbx_template:FBXElem, settings:FBXImportSettings):*{
		if(this.bl_obj){
			return this.bl_obj;
		}
		if((this.is_bone) || (this.fbx_elem != null)){
			return null;
		}
		var elem_name:String = this.fbx_name;
		
	}
	public function build_skeleton_children(fbx_template:FBXElem, settings:FBXImportSettings):void{
		
	}
	public function link_skeleton_children():void{
		trace("link skeleton children");
	}
	public function set_pose_matrix():void{
		trace("set pose matrix");
	}
	public function merge_weights():void{
		trace("merge weights");
	}
	public function set_bone_weights():void{
		trace("set bone weights");
	}
	public function build_hierarchy(fbx_template:FBXElem, settings:FBXImportSettings, scene:Scene3D):void{
		trace("Build Hierarchy");
		if(this.is_armature){
			trace("is Armature");
		}else if((this.fbx_elem != null) && (this.is_bone)){
			trace("is Bone");
		}else{
			for(var i:int = 0; i < this.children.length; i++){
				var child:FBXImportHelperNode = this.children[i];
				child.build_hierarchy(fbx_template, settings, scene);
			}
			return;
		}
		
	}
	
	
	public function link_hierarchy(fbx_template:FBXElem, settings:FBXImportSettings, scene:Scene3D):void{
		if(this.is_armature){
			var arm:* = this.bl_obj;
			//link bone children
			for(var i:int = 0; i < this.children; i++){
				var child:FBXImportHelperNode = this.children[i];
				//if(child.ignore){
				//	continue;
				//}
				//var child_obj = child.link_skeleton_children(fbx_template, settings, scene);
				
			}
		}
	}
	
}
internal class FBXTransformData{
	public var loc:Vector3D;
	public var rot:Vector3D;
	public var sca:Vector3D;
	public var geom_loc:Vector3D;
	public var geom_rot:Vector3D;
	public var geom_sca:Vector3D;
	public var rot_ofs:Vector3D;
	public var rot_piv:Vector3D;
	public var sca_ofs:Vector3D;
	public var sca_piv:Vector3D;
	public var pre_rot:Vector3D;
	public var pst_rot:Vector3D;
	public var rot_order:String;
	public var rot_alt_mat:Matrix3D;
	public function FBXTransformData(loc:Vector3D, geom_loc:Vector3D,rot:Vector3D, rot_ofs:Vector3D, rot_piv:Vector3D, pre_rot:Vector3D, pst_rot:Vector3D, rot_ord:String, rot_alt_mat:Matrix3D, geom_rot:Vector3D,sca:Vector3D, sca_ofs:Vector3D, sca_piv:Vector3D, geom_scal:Vector3D){
		this.loc = loc;
		this.geom_loc = geom_loc;
		this.rot = rot;
		this.rot_ofs = rot_ofs;
		this.rot_piv = rot_piv;
		this.pre_rot = pre_rot;
		this.pst_rot = pst_rot;
		this.rot_order = rot_order;
		this.rot_alt_mat = rot_alt_mat;
		this.geom_rot = geom_rot;
		this.sca = sca;
		this.sca_ofs = sca_ofs;
		this.sca_piv = sca_piv;
		this.geom_sca = geom_sca;	
	}
}
internal class FBXImportSettings{
	public var axis_up:String = "Y";
	public var axis_forward:String = "-Z";
	public var global_matrix:Matrix3D;
	public var global_scale:Number = 1;
	public var bake_space_transform:Boolean = false;
	public var global_matrix_inv:Matrix3D;
	public var global_matrix_inv_transposed:Matrix3D;
	public var use_custom_normals:Boolean = true;
	public var use_image_search:Boolean = false;
	public var use_alpha_decals:Boolean = false;
	public var decal_offset:Number = 0;
	public var use_anim:Boolean = true;
	public var anim_offset:Number = 1;
	public var use_custom_props:Boolean = true;
	public var use_custom_props_enum_as_string:Boolean = true;
	public var cycles_material_wrap_map:Array = [];
	public var image_cache:Array = [];
	public var ignore_leaf_bones:Boolean = false;
	public var force_connect_children:Boolean = false;
	public var automatic_bone_orientation:Boolean = false;
	public var bone_correction_matrix:Matrix3D = null;
	public var use_prepost_rot:Boolean = true;
}