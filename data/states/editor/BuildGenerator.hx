
import funkin.options.TreeMenu;
import funkin.options.TreeMenuScreen;
import funkin.options.type.Checkbox;
import funkin.options.type.TextOption;
import funkin.options.type.Separator;
import funkin.options.type.OptionType;
import funkin.options.type.PortraitOption;

import funkin.backend.assets.ModsFolder;

import funkin.backend.utils.ZipUtil;
import funkin.backend.utils.NativeAPI;
import funkin.backend.utils.FileAttribute;

import funkin.backend.utils.ThreadUtil;

import funkin.backend.system.Logs;

import funkin.backend.system.Flags;
import funkin.backend.system.macros.GitCommitMacro;

import funkin.editors.ui.UISliceSprite;

import funkin.menus.ui.Alphabet;
import funkin.menus.ui.AlphabetAlignment;
import funkin.menus.ui.effects.WaveEffect;

import sys.io.File;
import sys.FileSystem;

import haxe.ds.StringMap;
import haxe.io.Path;

import flixel.utils.FlxAxes;

import flixel.effects.FlxFlicker;

import flixel.text.FlxTextFormat;
import flixel.text.FlxTextFormatMarkerPair;
import flixel.text.FlxTextBorderStyle;

import Sys;

using StringTools;

class FileUtil {

	private static function hard_delete_folder(path:String) {
		CoolUtil.deleteFolder(BuildData.modpack_export_path);
		if (FileSystem.exists(BuildData.modpack_export_path)) FileSystem.deleteDirectory(BuildData.modpack_export_path);
	}

	private static function precheckFolders(input_path:String, input_destPath:String, ?exclude:Array<String> = []):Array<{folder:String, fPath:String, fDest:String}> {
		var folders:Array<{folder:String, fPath:String, fDest:String}> = [];
		for (folder in FileSystem.readDirectory(input_path)) {
			if (exclude.contains('$input_path/$folder')) continue;
			if (FileSystem.isDirectory('$input_path/$folder')) {
				folders.push({ folder: '$input_destPath/$folder' });
				folders = folders.concat(FileUtil.precheckFolders('$input_path/$folder', '$input_destPath/$folder', exclude));
			}
			else folders.push({ fPath: '$input_path/$folder', fDest: '$input_destPath/$folder'});
		}
		return folders;
	}

	public static function copy_folder(path:String, destPath:String, ?exclude:Array<String>, ?onComplete:Void->Void, ?onError:Void->Void, ?onProgress:Float->Void) {
		var path = path;
		var destPath = destPath;

		var exclude = exclude;
		var complete = onComplete;
		var failed = onError;
		var progress = onProgress;

		ThreadUtil.execAsync(() -> {
			FileUtil.copy_folder_unthreaded(path, destPath, exclude, complete, failed, progress);
		});
	}

	public static function copy_folder_unthreaded(path:String, destPath:String, ?exclude:Array<String>, ?onComplete:Void->Void, ?onError:Void->Void, ?onProgress:Float->Void) {
		var path = path; // because of how functions work they aren't real variables, this allows for sub-functions to recognize the variables
		var destPath = destPath;
		var onProgress = onProgress;

		var exclude = exclude ?? [];
		var complete = onComplete ?? () -> {};
		var failed = onError ?? () -> {};
		var progress = (p, max) -> {
			if (onProgress == null) return;
			try { onProgress(p, max); } catch(e:Error) { }
		};

		CoolUtil.addMissingFolders(path);
		CoolUtil.addMissingFolders(destPath);

		var copied:Int = 0;
		var folders:Array<{folder:String, fPath:String, fDest:String}> = FileUtil.precheckFolders(path, destPath, exclude);

		progress(copied, folders.length);
		for (data in folders) {
			if (data.folder != null) {
				CoolUtil.addMissingFolders(data.folder);
				progress((copied++)/folders.length, folders.length);
				continue;
			}
			try { File.copy(data.fPath, data.fDest); }
			catch(e:Error) { failed(e); }
			progress((copied++)/folders.length, folders.length);
		}
		progress(1, folders.length);
		complete();
	}
}

function create() {
	if (ModsFolder.currentModFolder == null) {
		addMenu(new TreeMenuScreen("Invalid mod!", "Your trying to generate a build for the Assets folder... lol", null, []));
		return;
	}
	BuildData.init_settings();
	BuildData.update_ignore_list();

	addMenu(new TreeMenuScreen("Final Export", "", null, parseData(BuildData.generate())));
}

//region Classes and stuff

class ProgressBar extends UISliceSprite {
    public static var UPDATE_FIX:Array<ProgressBar> = [];
    public var progress:Float = 0;

    public var fill_bar:UISliceSprite;

    private var display_text:Alphabet;
    public var text:String = "";

    public function new(w:Int, h:Int, ?_text:String) {
        super(0, 0, w, h, 'editors/ui/button');
        fill_bar = new UISliceSprite(0, 0, w, h, 'editors/ui/button');
        fill_bar.framesOffset = 18;
        
        display_text = new Alphabet(0, 0, "hi !!", 'normal');
        display_text.scale.set(0.35, 0.35);
        display_text.updateHitbox();

        this.text = (_text ?? "");
        ProgressBar.UPDATE_FIX.push(this);
        this.progress = 0;
    }

    public override function resize(w:Int, h:Int) {
        super.resize(w, h);
        fill_bar.resize(w, h);
    }

    public override function draw() {
        super.draw();
        fill_bar.draw();
        display_text.draw();
    }

    public function _update(elapsed:Float) {
        this.update(elapsed);
        fill_bar.update(elapsed);
        display_text.update(elapsed);

        fill_bar.x = this.x;
        fill_bar.y = this.y;

        display_text.x = this.x + (this.bWidth - display_text.width) * 0.5;
        display_text.y = this.y + (this.bHeight) + 10;

        fill_bar.bWidth = Std.int(this.bWidth * this.progress);
        
        var percentString = Math.floor(this.progress * 100)+'.'+CoolUtil.addEndZeros(Math.floor(((this.progress * 100) % 1) * 100), 2);
        display_text.text = this.text + "\n(" + percentString+"%)";
        display_text.updateHitbox();
        display_text.alignment = AlphabetAlignment.CENTER;
    }
}

class SpinnerHandler {
    static var SPINNER_ITEMS:Array<SpinnerHandler> = [];

    static function remove(item:Dynamic) {
        if (item is FlxSprite) for (i in SpinnerHandler.SPINNER_ITEMS) if (i.sprite == item) return i.remove();
        if (item is SpinnerHandler) return item.remove();
    }

    public var sprite:FlxSprite;

    public var spin_speed:Float;

    public function new(sprite:FlxSprite, ?spin_speed:Float = 1) {
        this.spin_speed = (spin_speed ?? 1);
        this.sprite = sprite;
        SpinnerHandler.SPINNER_ITEMS.push(this);
    }

    public function update(elapsed:Float) {
        sprite.angle = (sprite.angle + ((500 * spin_speed) * elapsed)) % 360;
    }

    public function remove() {
        sprite.angle = 0;
        SpinnerHandler.SPINNER_ITEMS.remove(this);
    }
}

class BuildData {

	public static var BUILD_IGNORE_DATA:Map<String, Map<String, String>> = (Assets.exists("data/config/build_ignore.ini") ? IniUtil.parseAsset("data/config/build_ignore.ini") : new StringMap());

	public static function init_settings() {
		if (!BUILD_IGNORE_DATA.exists("Settings")) return;
		var settings:Map<String, String> = BUILD_IGNORE_DATA.get("Settings");
		
		if (settings.exists("COMPRESS")) BuildData.export_as_compressed_mod = ((settings.get("COMPRESS").trim().toLowerCase()) == "true");
		if (settings.exists("CNE_MOD")) BuildData.export_as_cne_mod = ((settings.get("CNE_MOD").trim().toLowerCase()) == "true");
		if (settings.exists("EXE_BUILD")) BuildData.export_as_executable = ((settings.get("EXE_BUILD").trim().toLowerCase()) == "true");
	}

	public static var NEVER_CHECK:Array<String> = [".git", ".gitignore", ".github", ".vscode", ".gitattributes"];
	public static var IGNORE_LIST:StringMap<String> = new StringMap(); // folder_name => [files.ext]
	public static function update_ignore_list() {
		for (key=>value in BUILD_IGNORE_DATA) {
			if (!key.startsWith("./")) continue;

			var ignore:Bool = (value.exists("KEEP_FOLDER") ? ((value.get("KEEP_FOLDER").trim().toLowerCase()) == "true") : true);

			var folder_name:String = key.substr(2);
			if (folder_name.charAt(folder_name.length-1) == "/") folder_name = folder_name.substr(0, folder_name.length-1);

			var data:{keep:Bool, remove:Array<String>} = {keep: ignore, remove: []};
			if (value.exists("REMOVE")) data.remove = [for (item in value.get("REMOVE").split(",")) if (item.trim() != "") item.trim()];
			IGNORE_LIST.set(folder_name, data);
		}
		if (IGNORE_LIST.exists("data/config")) IGNORE_LIST.get("data/config").remove.push("build_ignore.ini");
		else IGNORE_LIST.set("data/config", {keep: true, remove: ['build_ignore.ini']});
	}

	public static var export_path:String = ".export/";
	public static var ico_text:String = "[.ShellClassInfo]\nIconResource=modicon.ico,0";
	public static var mod_path:String = '${ModsFolder.modsPath}${ModsFolder.currentModFolder}';
	public static var mod_folder_name:String = ModsFolder.currentModFolder;

	public static var cache_autoPause = FlxG.autoPause;

	public static var KEEP_FOLDER_NAME:String = "Keep Folder";

	public static var build_options = {
		type: TreeMenuScreen,
		name: "Build Options",
		desc: "How you want your build to be exported.\n",
		children: [
			{
				type: Checkbox,
				name: "Compressed Mod",
				desc: "If true, exports the build as a .zip (Also known as a Compressed Mod)",
				checked: true,
				callback: (box, children) -> BuildData.build_options.children[1].locked = children[1].locked = !box.checked
			},
			{
				type: Checkbox,
				name: "Export as CNE Mod",
				desc: "If true, exports the build as a CodenameEngine Mod.\nThe folder icon will be the mod's Icon!
				(Only visually affects Windows users, but works on all supported platforms)",
				checked: true,
				locked: false
			},
			// maybe add an option to include the un-compressed mod as well if your compressing?
			{type: Separator, height: 50},
			{
				type: Checkbox,
				name: "Compile into\nExecutable",
				desc: "If checked, the export will also contain a Compiled folder that contains the Exectuable that you are using right now, inside it!
				!!WARNING!! | This can take a while to compile depending on the size of the mod, so be patient!",
				checked: false,
				locked: false
			}
		]
	};
	
	public static var export = { 
        type: PortraitOption,
        name: "Export",
        desc: "Builds your mod and puts it in the '.export/' folder",
		locked: false,
        callback: (item, children) -> {
			FlxFlicker.stopFlickering(item);
			BuildData.build(item, children);
		},
        icon: {
            name: "editors/exporter-menu",
            size: 96,
            offset: FlxPoint.get(0, 5),
        },
        color: 0xFF00d9b7,
        onGenerate: (item, children) -> {
            var test = new ProgressBar(350, 15, "Ready For Export.");
            test.x += 15;
            test.y = item.height - 5;
            item.add(test);
        },
    };

	public static function generate() {
		return [
			build_options,
			export,
		];
	}

	public static var export_as_compressed_mod(get, set):Bool;
	private static function get_export_as_compressed_mod() return BuildData.build_options.children[0].checked && !BuildData.build_options.children[0].locked;
	private static function set_export_as_compressed_mod(value:Bool) { BuildData.build_options.children[0].checked = value; return value; }

	public static var export_as_cne_mod(get, set):Bool;
	private static function get_export_as_cne_mod() return BuildData.build_options.children[1].checked && !BuildData.build_options.children[1].locked;
	private static function set_export_as_cne_mod(value:Bool) { BuildData.build_options.children[1].checked = value; return value; }

	public static var export_as_executable(get, set):Bool;
	private static function get_export_as_executable() return BuildData.build_options.children[3].checked && !BuildData.build_options.children[3].locked;
	private static function set_export_as_executable(value:Bool) { BuildData.build_options.children[3].checked = value; return value; }

	public static var BUILDING_FAILED:Bool = false;

	public static var modpack_export_path:String = '$export_path$mod_folder_name (Uncompressed)/';

	private static var CURRENT_PROGRESS:ProgressBar = null;
	private static function build_animation(item, children) {
        CURRENT_PROGRESS = item.members.filter(item -> ProgressBar.UPDATE_FIX.contains(item)).pop();
		cache_autoPause = FlxG.autoPause;
		FlxG.autoPause = false;
		for (item in children) {
			if (item.locked == null) continue;
			item.locked = true;
		}
		item.color = BuildData.export.color;
		
        item.addPortrait(FlxG.bitmap.add(Paths.image('editors/throbber')));
        item.portrait.setPosition(item.x + 90 - item.portrait.width, item.y + 10);
        new SpinnerHandler(item.portrait);
        
        var waveEffect = new WaveEffect(2.5, 5, 10);
        item.__text.effects.push(waveEffect);
		FlxTween.tween(waveEffect, {speed: 2.5, period: 5}, 1, {ease: FlxEase.quadOut});
	}
	
	// returns true if the build failed
	private static function check_failure() {
		if (BuildData.BUILDING_FAILED) {
			_log([Logs.logText("Build Failed!", 12)]);
			build_finished(item, children);
			return true;
		}
		return false;
	}

	// I think I hate threads now :)
	private static var _BUILD_ITEM_CACHE:FlxBasic = null;
	private static var _BUILD_CHILDREN_CACHE:FlxBasic = null;

	
	private static function clear_readonly_attributes(folder_dir:String) {
		if (!FileSystem.exists(folder_dir) || !FileSystem.isDirectory(folder_dir)) return;
		for (folder in FileSystem.readDirectory(folder_dir)) {
			var sub_folder:String = '$folder_dir/$folder/';
			clear_readonly_attributes(sub_folder);
			var att = CoolUtil.safeGetAttributes(sub_folder);
			att.isReadOnly = false;
			CoolUtil.safeSetAttributes(sub_folder, att);
		}
	}

	public static function build(item, children) {
		BuildData._BUILD_ITEM_CACHE = item;
		BuildData._BUILD_CHILDREN_CACHE = children;
		build_animation(BuildData._BUILD_ITEM_CACHE, BuildData._BUILD_CHILDREN_CACHE);

		if (ThreadUtil.execAsync == null) {
			BuildData.CURRENT_PROGRESS.text = (
			'ERROR! This version of CodenameEngine doesn\'t support the `ThreadUtil.execAsync`
			function. Please report this error on the GitHub with the Commit Hash of this build.
				
			Hash: ${GitCommitMacro.commitHash}
			Branch: ${GitCommitMacro.currentBranch}');
			BuildData.CURRENT_PROGRESS.screenCenter(FlxAxes.X);
			return;
		}

		ThreadUtil.execAsync(() -> {
			BuildData.CURRENT_PROGRESS.text = "Cleaning Export Folder...";
			BuildData.clear_readonly_attributes(BuildData.export_path);
		
			CoolUtil.deleteFolder(BuildData.export_path); // delete all the contents of the folder
			CoolUtil.addMissingFolders(BuildData.export_path); // re-add the folder :tr:

			try{ BuildData.prepare_modpack(); } catch(e:Error) {
				BuildData.BUILDING_FAILED = true;
				BuildData.check_failure();
				return;
			}
			if (BuildData.check_failure()) return;

			if (BuildData.export_as_compressed_mod) {
				try{ BuildData.prepare_compressed_modpack(); } catch(e:Error) {
					BuildData.BUILDING_FAILED = true;
					BuildData.check_failure();
					return;
				}
			} else if (FileSystem.exists(BuildData.modpack_export_path)) {
				FileSystem.rename(BuildData.modpack_export_path,
				'${BuildData.export_path}/${BuildData.mod_folder_name}');
			}
			if (BuildData.check_failure()) return;
			FileUtil.hard_delete_folder(BuildData.modpack_export_path);

			if (BuildData.export_as_executable) BuildData.build_executable();
			if (BuildData.check_failure()) return;

			BuildData.build_finished();
			_log([Logs.logText("Build Complete!", -1)]);
		});
	}

	private static function build_finished() {
		var item = BuildData._BUILD_ITEM_CACHE;
		var children = BuildData._BUILD_CHILDREN_CACHE;

		final time:Float = 0.8;
		FlxTween.tween(CURRENT_PROGRESS, { progress: 0 }, time, { ease: FlxEase.quartOut, startDelay: 0.5,
            onStart: () -> {
                for (effect in item.__text.effects) {
                    if (!(effect is WaveEffect)) continue;
                    FlxTween.tween(effect, { intensityY: 0, intensityX: 0 }, time, {ease: FlxEase.quadOut});
                }
            }, onComplete: () -> {
                CURRENT_PROGRESS.text = "Ready For Export.";
				FlxG.autoPause = cache_autoPause;
				for (child in children) {
					if (child.locked == null) continue;
					child.locked = false;
				}
				item.__text.color = BuildData.export.color;
				SpinnerHandler.remove(item.portrait);
				item.addPortrait(FlxG.bitmap.add(Paths.image(BuildData.export.icon.name)));
				item.portrait.setPosition(item.x + 90 - item.portrait.width, item.y + 10);
        }});
	}

	// This will copy the folders to the `./exports/` folder, and also ignore the folders and files requested.
	private static function prepare_modpack() {
		var progress_text:String = "Exporting Mod...";

		BuildData._log([Logs.logText("Preparing Modpack...", -1)], 0);
		BuildData.CURRENT_PROGRESS.text = "Preparing Modpack...";
		
		var ignore_list:Array<String> = [];
		for (key=>value in IGNORE_LIST) {
			if (!value.keep) ignore_list.push('${BuildData.mod_path}/$key');
			else for (item in value.remove) ignore_list.push('${BuildData.mod_path}/$key/$item');
		}

		CoolUtil.addMissingFolders(modpack_export_path);
		FileUtil.copy_folder_unthreaded(BuildData.mod_path, modpack_export_path, ignore_list, () -> {
			_log([Logs.logText("Modpack Export Complete!", -1)]);
		}, (e) -> {
			_log([Logs.logText("Failed to export modpack!", -1), Logs.logText('\n$e', 12)]);
			BuildData.BUILDING_FAILED = true;
		}, (p, max) -> {
			CURRENT_PROGRESS.progress = p;
			BuildData.CURRENT_PROGRESS.text = progress_text;
		});
	}

	private static function set_attributes_for_cne_mod(folder:String) {
		var iniAtt = CoolUtil.safeGetAttributes('$folder/desktop.ini');
		iniAtt.isHidden = true;

		var modFolderAtt = CoolUtil.safeGetAttributes(folder);
		modFolderAtt.isReadOnly = true;
		
		CoolUtil.safeSetAttributes('$folder/desktop.ini', iniAtt);
		CoolUtil.safeSetAttributes(folder, modFolderAtt);
	}

	// this will take the modpack generated in `./exports/` and then compress it into a `.zip` file.
	private static function prepare_compressed_modpack() {
		var progress_text:String = "Compressing Mod...";

		BuildData._log([Logs.logText("Preparing Compressed Mod...", -1)], 0);
		BuildData.CURRENT_PROGRESS.text = "Preparing Compressed Mod...";

		var path:String = '${BuildData.export_path}/';
		path += (export_as_cne_mod) ? '${BuildData.mod_folder_name}/cnemod.zip' : (!export_as_executable) ? "Final Modpack Build.zip" : '${BuildData.mod_folder_name}.zip';
		CoolUtil.addMissingFolders(Path.directory(path));

		if (export_as_cne_mod) {
			var _folder_path:String = '${BuildData.export_path}/${BuildData.mod_folder_name}/';
            CoolUtil.safeSaveFile('$_folder_path/desktop.ini', BuildData.ico_text);

            var modIcon_ico = '${Path.withoutExtension(Flags.MOD_ICON)}.ico';
			var path:String = '${BuildData.mod_path}/$modIcon_ico';
            if (!FileSystem.exists(path)) modIcon_ico = "./icon.ico";
            else modIcon_ico = path;
            File.copy(modIcon_ico, '$_folder_path/modicon.ico');
			BuildData.set_attributes_for_cne_mod(_folder_path);
		}
        
		var writter:ZipUtil = ZipUtil.createZipFile(path);
        var progress:ZipProgress = ZipUtil.writeFolderToZipAsync(writter, modpack_export_path);
		
		while(!progress.done) {
			CURRENT_PROGRESS.progress = progress.percentage;
			BuildData.CURRENT_PROGRESS.text = '$progress_text\nFiles Compressed: ${progress.curFile}/${progress.fileCount}';
		}
		CURRENT_PROGRESS.progress = 1;
		BuildData.CURRENT_PROGRESS.text = '$progress_text\nFiles Compressed: ${progress.fileCount}/${progress.fileCount}';
		writter.o.close();
	}

	private static var EXECUTABLE_BUILD_FOLDER:String = '$export_path/Executable Build/';
	private static function build_executable() {
		var progress_text:String = "Compiling Executable...";
		var copy_mod_text:String = "Saving Mod...";

		BuildData._log([Logs.logText("Preparing Executable...", -1)], 0);
		
		CURRENT_PROGRESS.progress = 0;
		BuildData.CURRENT_PROGRESS.text = "Preparing Executable...";
		
		CoolUtil.addMissingFolders(Path.directory(BuildData.EXECUTABLE_BUILD_FOLDER));

        var ignore_list:Array<String> = ["./.export", "./.temp", "./mods", "./addons"];
		ignore_list = ignore_list.concat(NEVER_CHECK);

		function copy_once_more() {
			CURRENT_PROGRESS.progress = 0;
			BuildData.CURRENT_PROGRESS.text = copy_mod_text;

			var path:String = '${BuildData.EXECUTABLE_BUILD_FOLDER}/mods/${BuildData.mod_folder_name}';
			CoolUtil.addMissingFolders(Path.directory(path));

			CoolUtil.safeSaveFile('${BuildData.EXECUTABLE_BUILD_FOLDER}/mods/autoload.txt', BuildData.mod_folder_name);

			var copy_path:String = '${BuildData.export_path}/${BuildData.mod_folder_name}';
			if (BuildData.export_as_compressed_mod && !BuildData.export_as_cne_mod) File.copy('${copy_path}.zip', '$path.zip');
			else {
				FileUtil.copy_folder_unthreaded(copy_path, path, [], () -> {
					if (BuildData.export_as_cne_mod) BuildData.set_attributes_for_cne_mod(path);
					_log([Logs.logText("Executable Export Complete!", -1)]);
				}, (e) -> {
					_log([Logs.logText("Failed to export executable!", -1), Logs.logText('\n$e', 12)]);
					BuildData.BUILDING_FAILED = true;
				}, (p, max) -> {
					CURRENT_PROGRESS.progress = p;
					BuildData.CURRENT_PROGRESS.text = copy_mod_text;
				});
			}
		}

		FileUtil.copy_folder_unthreaded(".", BuildData.EXECUTABLE_BUILD_FOLDER, ignore_list, copy_once_more, (e) -> {
			_log([Logs.logText("Failed to export executable!", -1), Logs.logText('\n$e', 12)]);
			BuildData.BUILDING_FAILED = true;
		}, (p, max) -> {
			CURRENT_PROGRESS.progress = p;
			BuildData.CURRENT_PROGRESS.text = progress_text;
		});
	}

	/*
		BLACK = 0;  DARKBLUE = 1;  DARKGREEN = 2;  DARKCYAN = 3;  DARKRED = 4;  DARKMAGENTA = 5;
        DARKYELLOW = 6;  LIGHTGRAY = 7;  GRAY = 8;  BLUE = 9;  GREEN = 10;  CYAN = 11;  RED = 12;
        MAGENTA = 13;  YELLOW = 14;  WHITE = 15;

		NONE = -1;
		use case: _log(Logs.logText("Hello World!", -1), 0);
	*/
    private static function _log(logText:Array, ?type:Int) {
		logText ??= [];
        if (logText.length <= 0) return;
        type ??= 0;
        logText.insert(0, Logs.logText("[Final Build Generator] ", 1));
        Logs.traceColored(logText, type);
    }
}

//endregion

var CURRENT_STATE:TreeMenu = null;
var _prev_label_text:String = "";

function update(elapsed:Float) {
    for (item in ProgressBar.UPDATE_FIX) item._update(elapsed);
    for (item in SpinnerHandler.SPINNER_ITEMS) item.update(elapsed);

	if (CURRENT_STATE != null) {
		if (_prev_label_text != CURRENT_STATE.descLabel.text) {
			CURRENT_STATE.descLabel.applyMarkup(CURRENT_STATE.descLabel.text, DEFAULT_MARKUP);
			_prev_label_text = CURRENT_STATE.descLabel.text;
		}
	}
}

final DEFAULT_MARKUP:Array<FlxTextFormatMarkerPair> = [
    new FlxTextFormatMarkerPair(new FlxTextFormat(FlxColor.RED), "[red]"),
    new FlxTextFormatMarkerPair(new FlxTextFormat(FlxColor.ORANGE), "[orange]"),
    new FlxTextFormatMarkerPair(new FlxTextFormat(FlxColor.YELLOW), "[yellow]"),
    new FlxTextFormatMarkerPair(new FlxTextFormat(FlxColor.GREEN), "[green]"),
    new FlxTextFormatMarkerPair(new FlxTextFormat(FlxColor.BLUE), "[blue]"),
    new FlxTextFormatMarkerPair(new FlxTextFormat(FlxColor.PURPLE), "[purple]"),
    new FlxTextFormatMarkerPair(new FlxTextFormat(FlxColor.PINK), "[pink]"),
    new FlxTextFormatMarkerPair(new FlxTextFormat(FlxColor.CYAN), "[cyan]"),
    new FlxTextFormatMarkerPair(new FlxTextFormat(FlxColor.GRAY), "[gray]"),
    new FlxTextFormatMarkerPair(new FlxTextFormat(0xFFAFAFAF), "[l_gray]"),
    new FlxTextFormatMarkerPair(new FlxTextFormat(FlxColor.LIME), "[lime]"),
];

function parseData(data:Array<Dynamic>) {
	var children = [
		for (info in data) {
			switch (info.type) {
				case TreeMenuScreen:
					new TextOption(info.name, info.desc, " >", () -> {
						var children = parseData(info.children);
						var new_state = new TreeMenuScreen(info.name, info.desc, null, children);
						new_state.onClose.add(() -> {
							if (info.onClose != null) info.onClose(new_state, children);
							CURRENT_STATE = null;
						});
						addMenu(new_state);
						// CURRENT_STATE = new_state.parent; // commenting it out for now, it's a bit buggy
					});
				case Checkbox:
					var box = new Checkbox(info.name, info?.desc ?? "", null);
					box.checked = info?.checked ?? false;
					box;
				case Separator:
					new Separator(info.height);
				case TextOption:
					new TextOption(info.name, info.desc, info.suffix);
				case PortraitOption:
					var port = new PortraitOption(info.name, info.desc, null, FlxG.bitmap.add(Paths.image(info.icon.name)), (info.icon?.size ?? 96),
						(info.icon?.usePortrait ?? false));
					port?.portrait?.x += (info.icon?.offset?.x ?? 0);
					port?.portrait?.y += (info.icon?.offset?.y ?? 0);
					port;
			}
		}
	];
	for (idx => info in data) {
		var child = children[idx];
		if (!(child is OptionType)) continue;

		if (!(info.type == TreeMenuScreen))
			child.selectCallback = () -> {
				switch (info.type) {
					case Checkbox:
						info.checked = child.checked;
						info.locked = child.locked;
				}
				if (info.callback != null)
					info.callback(child, children);
			}
		
		if (info.type != Separator && info.locked != null) child.locked = info.locked;
		if (info.color != null) child.__text.color = info.color;
		if (info.onGenerate != null) info.onGenerate(child, children);
	}
	return children;
}