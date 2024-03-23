package funkin;

import funkin.ui.debug.charting.ChartEditorState;
import funkin.ui.transition.LoadingState;
import flixel.FlxState;
import flixel.addons.transition.FlxTransitionableState;
import flixel.addons.transition.FlxTransitionSprite.GraphicTransTileDiamond;
import flixel.addons.transition.TransitionData;
import flixel.graphics.FlxGraphic;
import flixel.math.FlxPoint;
import flixel.math.FlxRect;
import flixel.FlxSprite;
import flixel.system.debug.log.LogStyle;
import flixel.util.FlxColor;
import funkin.util.macro.MacroUtil;
import funkin.util.WindowUtil;
import funkin.play.PlayStatePlaylist;
import openfl.display.BitmapData;
import funkin.data.level.LevelRegistry;
import funkin.data.notestyle.NoteStyleRegistry;
import funkin.data.event.SongEventRegistry;
import funkin.data.stage.StageRegistry;
import funkin.data.dialogue.ConversationRegistry;
import funkin.data.dialogue.DialogueBoxRegistry;
import funkin.data.dialogue.SpeakerRegistry;
import funkin.data.freeplay.AlbumRegistry;
import funkin.data.song.SongRegistry;
import funkin.play.character.CharacterData.CharacterDataParser;
import funkin.modding.module.ModuleHandler;
import funkin.ui.title.TitleState;
import funkin.util.CLIUtil;
import funkin.util.CLIUtil.CLIParams;
import funkin.util.TimerUtil;
import funkin.util.TrackerUtil;
#if discord_rpc
import Discord.DiscordClient;
#end

/**
 * A core class which performs initialization of the game.
 * The initialization state has several functions:
 * - Calls code to set up the game, including loading saves and parsing game data.
 * - Chooses whether to start via debug or via launching normally.
 *
 * It should not contain any sprites or rendering.
 */
class InitState extends FlxState
{
  /**
   * Perform a bunch of game setup, then immediately transition to the title screen.
   */
  public override function create():Void
  {
    // Setup a bunch of important Flixel stuff.
    setupShit();

    // Load player options from save data.
    // Flixel has already loaded the save data, so we can just use it.
    Preferences.init();

    // Load controls from save data.
    PlayerSettings.init();

    startGame();
  }

  /**
   * Setup a bunch of important Flixel stuff.
   */
  function setupShit():Void
  {
    //
    // GAME SETUP
    //

    // Setup window events (like callbacks for onWindowClose)
    WindowUtil.initWindowEvents();
    // Disable the thing on Windows where it tries to send a bug report to Microsoft because why do they care?
    WindowUtil.disableCrashHandler();

    // This ain't a pixel art game! (most of the time)
    FlxSprite.defaultAntialiasing = true;

    // Disable default keybinds for volume (we manually control volume in MusicBeatState with custom binds)
    FlxG.sound.volumeUpKeys = [];
    FlxG.sound.volumeDownKeys = [];
    FlxG.sound.muteKeys = [];

    // Set the game to a lower frame rate while it is in the background.
    FlxG.game.focusLostFramerate = 30;

    setupFlixelDebug();

    //
    // FLIXEL TRANSITIONS
    //

    // Diamond Transition
    var diamond:FlxGraphic = FlxGraphic.fromClass(GraphicTransTileDiamond);
    diamond.persist = true;
    diamond.destroyOnNoUse = false;

    // NOTE: tileData is ignored if TransitionData.type is FADE instead of TILES.
    var tileData:TransitionTileData = {asset: diamond, width: 32, height: 32};

    FlxTransitionableState.defaultTransIn = new TransitionData(FADE, FlxColor.BLACK, 1, new FlxPoint(0, -1), tileData,
      new FlxRect(-200, -200, FlxG.width * 1.4, FlxG.height * 1.4));
    FlxTransitionableState.defaultTransOut = new TransitionData(FADE, FlxColor.BLACK, 0.7, new FlxPoint(0, 1), tileData,
      new FlxRect(-200, -200, FlxG.width * 1.4, FlxG.height * 1.4));
    // Don't play transition in when entering the title state.
    FlxTransitionableState.skipNextTransIn = true;

    //
    // NEWGROUNDS API SETUP
    //
    #if newgrounds
    NGio.init();
    #end

    //
    // DISCORD API SETUP
    //
    #if discord_rpc
    DiscordClient.initialize();

    Application.current.onExit.add(function(exitCode) {
      DiscordClient.shutdown();
    });
    #end

    //
    // ANDROID SETUP
    //
    #if android
    FlxG.android.preventDefaultKeys = [flixel.input.android.FlxAndroidKey.BACK];
    #end

    //
    // FLIXEL PLUGINS
    //
    // Plugins provide a useful interface for globally active Flixel objects,
    // that receive update events regardless of the current state.
    // TODO: Move scripted Module behavior to a Flixel plugin.
    #if debug
    funkin.util.plugins.MemoryGCPlugin.initialize();
    #end
    funkin.util.plugins.EvacuateDebugPlugin.initialize();
    funkin.util.plugins.ForceCrashPlugin.initialize();
    funkin.util.plugins.ReloadAssetsDebugPlugin.initialize();
    funkin.util.plugins.ScreenshotPlugin.initialize();
    funkin.util.plugins.VolumePlugin.initialize();
    funkin.util.plugins.WatchPlugin.initialize();

    //
    // GAME DATA PARSING
    //

    // NOTE: Registries must be imported and not referenced with fully qualified names,
    // to ensure build macros work properly.
    trace('Parsing game data...');
    var perfStart:Float = TimerUtil.start();
    SongEventRegistry.loadEventCache(); // SongEventRegistry is structured differently so it's not a BaseRegistry.
    SongRegistry.instance.loadEntries();
    LevelRegistry.instance.loadEntries();
    NoteStyleRegistry.instance.loadEntries();
    ConversationRegistry.instance.loadEntries();
    DialogueBoxRegistry.instance.loadEntries();
    SpeakerRegistry.instance.loadEntries();
    AlbumRegistry.instance.loadEntries();
    StageRegistry.instance.loadEntries();

    // TODO: CharacterDataParser doesn't use json2object, so it's way slower than the other parsers and more prone to syntax errors.
    // Move it to use a BaseRegistry.
    CharacterDataParser.loadCharacterCache();

    ModuleHandler.buildModuleCallbacks();
    ModuleHandler.loadModuleCache();
    ModuleHandler.callOnCreate();

    trace('Parsing game data took: ${TimerUtil.ms(perfStart)}');
  }

  /**
   * Start the game.
   *
   * By default, moves to the `TitleState`.
   * But based on compile defines, the game can start immediately on a specific song,
   * or immediately in a specific debug menu.
   */
  function startGame():Void
  {
    #if SONG
    // -DSONG=bopeebo
    startSong(defineSong(), defineDifficulty());
    #elseif LEVEL
    // -DLEVEL=week1 -DDIFFICULTY=hard
    startLevel(defineLevel(), defineDifficulty());
    #elseif FREEPLAY
    // -DFREEPLAY
    FlxG.switchState(() -> new funkin.ui.freeplay.FreeplayState());
    #elseif DIALOGUE
    // -DDIALOGUE
    FlxG.switchState(() -> new funkin.ui.debug.dialogue.ConversationDebugState());
    #elseif ANIMATE
    // -DANIMATE
    FlxG.switchState(() -> new funkin.ui.debug.anim.FlxAnimateTest());
    #elseif WAVEFORM
    // -DWAVEFORM
    FlxG.switchState(() -> new funkin.ui.debug.WaveformTestState());
    #elseif CHARTING
    // -DCHARTING
    FlxG.switchState(() -> new funkin.ui.debug.charting.ChartEditorState());
    #elseif STAGEBUILD
    // -DSTAGEBUILD
    FlxG.switchState(() -> new funkin.ui.debug.stage.StageBuilderState());
    #elseif ANIMDEBUG
    // -DANIMDEBUG
    FlxG.switchState(() -> new funkin.ui.debug.anim.DebugBoundingState());
    #elseif LATENCY
    // -DLATENCY
    FlxG.switchState(() -> new funkin.LatencyState());
    #else
    startGameNormally();
    #end
  }

  /**
   * Start the game by moving to the title state and play the game as normal.
   */
  function startGameNormally():Void
  {
    var params:CLIParams = CLIUtil.processArgs();
    trace('Command line args: ${params}');

    if (params.chart.shouldLoadChart)
    {
      FlxG.switchState(() -> new ChartEditorState(
        {
          fnfcTargetPath: params.chart.chartPath,
        }));
    }
    else
    {
      FlxG.sound.cache(Paths.music('freakyMenu/freakyMenu'));
      FlxG.switchState(() -> new TitleState());
    }
  }

  /**
   * Start the game by directly loading into a specific song.
   * @param songId
   * @param difficultyId
   */
  function startSong(songId:String, difficultyId:String = 'normal'):Void
  {
    var songData:funkin.play.song.Song = funkin.data.song.SongRegistry.instance.fetchEntry(songId);

    if (songData == null)
    {
      startGameNormally();
      return;
    }

    LoadingState.loadPlayState(
      {
        targetSong: songData,
        targetDifficulty: difficultyId,
      });
  }

  /**
   * Start the game by directly loading into a specific story mode level.
   * @param levelId
   * @param difficultyId
   */
  function startLevel(levelId:String, difficultyId:String = 'normal'):Void
  {
    var currentLevel:funkin.ui.story.Level = funkin.data.level.LevelRegistry.instance.fetchEntry(levelId);

    if (currentLevel == null)
    {
      startGameNormally();
      return;
    }

    PlayStatePlaylist.playlistSongIds = currentLevel.getSongs();
    PlayStatePlaylist.isStoryMode = true;
    PlayStatePlaylist.campaignScore = 0;

    var targetSongId:String = PlayStatePlaylist.playlistSongIds.shift();

    var targetSong:funkin.play.song.Song = SongRegistry.instance.fetchEntry(targetSongId);

    LoadingState.loadPlayState(
      {
        targetSong: targetSong,
        targetDifficulty: difficultyId,
      });
  }

  function setupFlixelDebug():Void
  {
    //
    // FLIXEL DEBUG SETUP
    //
    #if (debug || FORCE_DEBUG_VERSION)
    // Make errors and warnings less annoying.
    // Forcing this always since I have never been happy to have the debugger to pop up
    LogStyle.ERROR.openConsole = false;
    LogStyle.ERROR.errorSound = null;
    LogStyle.WARNING.openConsole = false;
    LogStyle.WARNING.errorSound = null;

    // Disable using ~ to open the console (we use that for the Editor menu)
    FlxG.debugger.toggleKeys = [F2];
    TrackerUtil.initTrackers();
    // Adds an additional Close Debugger button.
    // This big obnoxious white button is for MOBILE, so that you can press it
    // easily with your finger when debug bullshit pops up during testing lol!
    FlxG.debugger.addButton(LEFT, new BitmapData(200, 200), function() {
      FlxG.debugger.visible = false;

      // Make errors and warnings less annoying.
      // Forcing this always since I have never been happy to have the debugger to pop up
      LogStyle.ERROR.openConsole = false;
      LogStyle.ERROR.errorSound = null;
      LogStyle.WARNING.openConsole = false;
      LogStyle.WARNING.errorSound = null;
    });

    // Adds a red button to the debugger.
    // This pauses the game AND the music! This ensures the Conductor stops.
    FlxG.debugger.addButton(CENTER, new BitmapData(20, 20, true, 0xFFCC2233), function() {
      if (FlxG.vcr.paused)
      {
        FlxG.vcr.resume();

        for (snd in FlxG.sound.list)
        {
          snd.resume();
        }

        FlxG.sound.music.resume();
      }
      else
      {
        FlxG.vcr.pause();

        for (snd in FlxG.sound.list)
        {
          snd.pause();
        }

        FlxG.sound.music.pause();
      }
    });

    // Adds a blue button to the debugger.
    // This skips forward in the song.
    FlxG.debugger.addButton(CENTER, new BitmapData(20, 20, true, 0xFF2222CC), function() {
      FlxG.game.debugger.vcr.onStep();

      for (snd in FlxG.sound.list)
      {
        snd.pause();
        snd.time += FlxG.elapsed * 1000;
      }

      FlxG.sound.music.pause();
      FlxG.sound.music.time += FlxG.elapsed * 1000;
    });
    #end
  }

  function defineSong():String
  {
    return MacroUtil.getDefine('SONG');
  }

  function defineLevel():String
  {
    return MacroUtil.getDefine('LEVEL');
  }

  function defineDifficulty():String
  {
    return MacroUtil.getDefine('DIFFICULTY');
  }
}
