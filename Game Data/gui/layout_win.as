#include "~/Game Data/gui/include/gui_skin.as"
#include "~/Game Data/gui/include/dialog.as"
#include "~/Game Data/gui/include/resource_grid.as"
#include "~/Game Data/gui/include/layout_stats.as"
#include "~/Game Data/gui/include/accordion.as"
#include "~/Game Data/gui/include/order_customizer.as"
#include "~/Game Data/gui/include/layout_import.as"
#include "~/Game Data/gui/include/layout_viewer.as"
#include "~/Game Data/gui/include/layout_detailed_stats.as"
#include "~/Game Data/gui/include/blueprints_sort.as"

import recti makeScreenCenteredRect(const dim2di &in rectSize) from "gui_lib";
import bool export_layout(const HullLayout@, string@, bool) from "layout_export";
import void showSubSystemDetails(uint) from "star_pedia";
import void anchorToMouse(GuiElement@) from "gui_lib";

/* {{{ Utilities */
string@ secondsToTime(int seconds) {
	if (seconds < 0)
		return "Inf";
	else if(seconds >= 3600) {
		int h = seconds / 3600;
		int m = (seconds % 3600) / 60;

		return (h + "h ") + (m + "m");
	}
	else if(seconds >= 600)
		return (seconds / 60) + "m";
	else if(seconds >= 60) {
		int s = seconds % 60;
		if(s > 0)
			return (seconds / 60) + "m " + (s + "s");
		else
			return (seconds / 60) + "m";
	}
	else {
		return seconds + "s";
	}
}

string@ secondsToTime(float secs) {
	int seconds = round(secs);

	if (seconds < 0)
		return "Inf";
	else if(seconds >= 3600) {
		int h = seconds / 3600;
		int m = (seconds % 3600) / 60;

		return h + "h " + m + "m";
	}
	else if(seconds >= 600)
		return (seconds / 60) + "m";
	else if(seconds >= 60) {
		int s = seconds % 60;
		if(s > 0)
			return (seconds / 60) + "m " + s + "s";
		else
			return (seconds / 60) + "m";
	}
	else if (secs <= 10.f) {
		return f_to_s(secs, 2) + "s";
	}
	else {
		return seconds + "s";
	}
}

string@ standardizeAndColor(float val) {
	if(val < 0)
		return combine("#c:red#", standardize(val), "#c#");
	else
		return combine("#c:green#", standardize(val), "#c#");
}

string@ strLocal = "Local/";
//Takes a statName (e.g. from a layout), a localeClass (e.g. #LH_)
//Returns the localized version of the statName
//If showLocals is false, returns null if the statName begins with "Local/"
string@ localizeStatName(const string@ statName, const string@ localeClass, bool showLocals) {
	if(!showLocals && statName.beginsWith(strLocal))
		return null;
	
	string@ result = localize(localeClass + statName);
	
	if(result.beginsWith(localeClass))
		result = statName;
	return result;
}

//Check if we can modify the position to be valid
bool makeDropPosition(pos2df& layPos, float scale, float extraDist) {
	float dist = sqrt(sqr(layPos.x) + sqr(layPos.y));
	float origDistance = dist + sqrt(scale) / 2;
	bool validPosition = origDistance < maxRadius;

	if (origDistance > maxRadius && dist - extraDist < maxRadius) {
		float factor = (maxRadius - sqrt(scale) / 2) / dist;
		layPos.x *= factor;
		layPos.y *= factor;
		return true;
	}

	return validPosition;
}

//Check if we're inside the ship circle
bool isValidPosition(const pos2df& layPos) {
	float distance = sqrt(sqr(layPos.x) + sqr(layPos.y));
	return distance < maxRadius;
}
/* }}} */
/* {{{ Layout Window Handle */
class LayoutWindowHandle {
	LayoutWindow@ script;
	GuiScripted@ ele;

	LayoutWindowHandle(recti Position) {
		@script = LayoutWindow();
		@ele = GuiScripted(Position, script, null);

		script.init(ele);
		script.syncPosition(Position.getSize());
	}

	void bringToFront() {
		ele.bringToFront();
		setGuiFocus(ele);
		bindEscapeEvent(ele);
	}

	void setVisible(bool vis) {
		ele.setVisible(vis);
		script.sysHoverName.setVisible(vis);
		if (script.draggingSys !is null)
			script.draggingSys.dragger.setVisible(vis);

		if (vis)
			bindEscapeEvent(ele);
		else
			clearEscapeEvent(ele);
	}

	void selectFirst() {
		script.updateLayoutList();
		if (script.blueprints.length() == 0)
			return;

		const HullLayout@ lay = script.blueprints.getLayout(0);
		script.selecting = true;
		@script.selectedLayout = lay;
		script.selectLayout(lay);
		script.layoutList.setSelected(0);
	}

	bool isVisible() {
		return ele.isVisible();
	}

	void update(float time) {
		script.update(time);
		script.position = ele.getPosition();
	}

	void remove() {
		clearEscapeEvent(ele);
		script.clearLayout();
		script.sysHoverName.remove();
		if (script.draggingSys !is null)
			script.draggingSys.dragger.remove();
		ele.remove();
		script.remove();
	}
};

/* }}} */
/* {{{ Layout Window Script */
const int TB_HEIGHT = 95;
const int MIN_WIDTH = 932;
const int MIN_HEIGHT = 543;
const int MAX_SYSLIST_WIDTH = 200;
const float unitsPerAU = 1000.f;

const float[] scaleValues = {0.5f, 1.f, 4.f, 8.f, 16.f, 32.f, 512.f, 4096.f};
const string[] scaleNames = {"#LES_Fighter", "#LES_Bomber", "#LES_Destroyer",
	"#LES_Frigate", "#LES_Cruiser", "#LES_Battleship", "#LES_Supercapital",
	"#LES_PlanetBuster"};

string@ localeLayoutCost = "#LC_", localeLayoutHint = "#LH_";
const string@ tagHull = "Hull", strHP = "HP", strMass = "Mass", tagStructure = "Structure";
const string@ strStrokedFont = "stroked";

enum LayoutTab {
	LT_List,
	LT_Layout,
	LT_Stats,
	LT_Settings,
};

enum DeltaMode {
	DM_DeltaOnly,
	DM_PrevDeltaResult
};

class QueuedLink {
	int primary;
	int secondary;
}

class LayoutWindow : ScriptedGuiHandler {
	DragResizeInfo drag;
	pos2di position;
	bool removed;

	subSysEntry@[] subSystems;
	QueuedLink@[] queuedLinks;
	HullStats@ lastStats;

	string@ error;
	bool hasError;
	bool hasHardError;

	float usedSpace;
	float maxSpace;

	LayoutWindow() {
		removed = false;
		hasHardError = false;
		hasError = false;
		usedSpace = 0;
		maxSpace = 0;
		@error = null;
	}

	void remove() {
		subSystems.resize(0);
		subSystemIcons.resize(0);
		subSystemLists.resize(0);
		subSystemAccordion.remove();
	}

	/* {{{ Main interface */
	GuiButton@ close;

	GuiPanel@ topPanel;
	GuiPanel@ listPanel;
	GuiPanel@ layoutPanel;
	GuiPanel@ statsPanel;
	GuiPanel@ settingsPanel;

	GuiStaticText@ nameText;
	GuiStaticText@ scaleText;

	GuiEditBox@ name;
	GuiEditBox@ scale;
	GuiButton@ pickScaleButton;

	GuiStaticText@ accelText;
	GuiStaticText@ accelValue;

	GuiStaticText@ flightText;
	GuiStaticText@ flightValue;

	GuiButton@ saveButton;
	GuiButton@ clearButton;
	GuiButton@ exportButton;
	GuiButton@ importButton;

	GuiButton@ listTab;
	GuiButton@ layoutTab;
	GuiButton@ statsTab;
	GuiButton@ settingsTab;

	ResourceGrid@ costTop;
	ResourceGrid@ costBottom;

	void init(GuiElement@ ele) {
		// Create top panel
		@topPanel = GuiPanel(recti(0, 20, 400, 70), false, SBM_Invisible, SBM_Invisible, ele);
		topPanel.fitChildren();

		@close = CloseButton(recti(), ele);

		// Data entries
		@nameText = GuiStaticText(recti(10, 7, 60, 27), localize("#LE_Name")+":", false, false, false, topPanel);
		@scaleText = GuiStaticText(recti(10, 29, 60, 49), localize("#LE_Scale")+":", false, false, false, topPanel);

		@name = GuiEditBox(recti(65, 7, 300, 27), null, true, topPanel);
		@scale = GuiEditBox(recti(65, 29, 270, 48), "1", true, topPanel);
		@pickScaleButton = Button(recti(273, 29, 300, 48), "...", topPanel);
		pickScaleButton.setToolTip(localize("#LE_PickScale"));

		// Quick stats
		@accelText = GuiStaticText(recti(323, 7, 415, 27), localize("#LE_Acceleration")+":", false, false, false, topPanel);
		@accelValue = GuiStaticText(recti(423, 7, 500, 27), "0.00", false, false, false, topPanel);

		@flightText = GuiStaticText(recti(323, 29, 415, 49), localize("#LE_FlightTime")+":", false, false, false, topPanel);
		@flightValue = GuiStaticText(recti(423, 29, 500, 49), "N/A", false, false, false, topPanel);

		// Cost icons
		@costTop = ResourceGrid(topPanel, pos2di(515, 7), dim2di(120, 17), 2);
		costTop.add(SR_AdvParts, 0);
		costTop.add(SR_Metals, 0);

		@costBottom = ResourceGrid(topPanel, pos2di(515, 29), dim2di(120, 17), 2);
		costBottom.add(SR_Electronics, 0);
		costBottom.add(SR_Labor, 0);

		// Action buttons
		@saveButton = Button(dim2di(70, 26), localize("#save"), topPanel);
		@clearButton = Button(dim2di(70, 26), localize("#clear"), topPanel);
		@exportButton = Button(dim2di(70, 26), localize("#export"), topPanel);
		@importButton = Button(dim2di(70, 26), localize("#import"), topPanel);

		saveButton.setToolTip(localize("#LETT_Save"));
		clearButton.setToolTip(localize("#LETT_Clear"));
		exportButton.setToolTip(localize("#LETT_Export"));
		importButton.setToolTip(localize("#LETT_Import"));

		// Tabs
		@listTab = TabButton(recti(), localize("#LB_BPList"), topPanel);
		@layoutTab = TabButton(recti(), localize("#LB_Layout"), topPanel);
		@statsTab = TabButton(recti(), localize("#LB_Stats"), topPanel);
		@settingsTab = TabButton(recti(), localize("#LB_AISettings"), topPanel);

		listTab.setPressed(true);

		// Create tab panels
		@listPanel = GuiPanel(recti(0, 0, 200, 50), false, SBM_Invisible, SBM_Invisible, ele);
		listPanel.fitChildren();

		@layoutPanel = GuiPanel(recti(0, 0, 200, 50), false, SBM_Invisible, SBM_Invisible, ele);
		layoutPanel.fitChildren();
		layoutPanel.setVisible(false);

		@statsPanel = GuiPanel(recti(0, 0, 200, 50), false, SBM_Invisible, SBM_Invisible, ele);
		statsPanel.fitChildren();
		statsPanel.setVisible(false);

		@settingsPanel = GuiPanel(recti(0, 0, 200, 50), false, SBM_Invisible, SBM_Invisible, ele);
		settingsPanel.fitChildren();
		settingsPanel.setVisible(false);

		// Initialise tabs
		initList(listPanel);
		initLayoutView(layoutPanel);
		initSettings(settingsPanel);
		initStats(statsPanel);
	}

	void syncPosition(dim2di size) {
		// Close button
		close.setPosition(pos2di(size.width-30, 0));
		close.setSize(dim2di(30, 12));

		// Position top panel
		topPanel.setPosition(pos2di(7, 19));
		topPanel.setSize(dim2di(size.width - 7, TB_HEIGHT - 12));

		saveButton.setPosition(pos2di(size.width - 154, 2));
		clearButton.setPosition(pos2di(size.width - 154, 28));

		exportButton.setPosition(pos2di(size.width - 85, 2));
		importButton.setPosition(pos2di(size.width - 85, 28));

		// Layout stats
		layoutStatsEle.setPosition(pos2di(size.width - 264, 47 + TB_HEIGHT));
		layoutStatsEle.setSize(dim2di(258, size.height - 54 - TB_HEIGHT));
		layoutStats.syncSize(layoutStatsEle.getSize());

		// Position tabs
		int tabSize = (size.width - 14 - 3*4) / 4;

		listTab.setPosition(pos2di(0, TB_HEIGHT - 35));
		layoutTab.setPosition(pos2di(4 + tabSize, TB_HEIGHT - 35));
		statsTab.setPosition(pos2di(8 + tabSize*2, TB_HEIGHT - 35));
		settingsTab.setPosition(pos2di(12 + tabSize*3, TB_HEIGHT - 35));
		
		listTab.setSize(dim2di(tabSize, 18));
		layoutTab.setSize(dim2di(tabSize, 18));
		statsTab.setSize(dim2di(tabSize, 18));
		settingsTab.setSize(dim2di(tabSize, 18));

		// Sync tab positions
		pos2di contentPos(0, TB_HEIGHT);
		dim2di contentSize = size - dim2di(0, TB_HEIGHT);

		listPanel.setPosition(contentPos);
		listPanel.setSize(contentSize);
		syncListPosition(contentSize);

		layoutPanel.setPosition(contentPos);
		layoutPanel.setSize(contentSize);
		syncLayoutViewPosition(contentSize);

		settingsPanel.setPosition(contentPos);
		settingsPanel.setSize(contentSize);
		syncSettingsPosition(contentSize);

		statsPanel.setPosition(contentPos);
		statsPanel.setSize(contentSize);
		syncStatsPosition(contentSize);
	}

	void draw(GuiElement@ ele) {
		ele.toGuiScripted().setAbsoluteClip();
		const recti absPos = ele.getAbsolutePosition();
		pos2di topLeft = absPos.UpperLeftCorner;
		pos2di botRight = absPos.LowerRightCorner;
		dim2di size = absPos.getSize();

		// Draw top area
		drawWindowFrame(absPos);
		drawResizeHandle(recti(botRight - pos2di(19, 19), botRight));
		drawTabBar(recti(topLeft + pos2di(6, TB_HEIGHT - 22), dim2di(size.width-12, 29)));
		drawDarkArea(recti(topLeft + pos2di(7, 20), dim2di(size.width-14, TB_HEIGHT - 41)));
		drawVSep(recti(topLeft + pos2di(316, 19), topLeft + pos2di(323, TB_HEIGHT - 20)));
		drawVSep(recti(topLeft + pos2di(505, 19), topLeft + pos2di(512, TB_HEIGHT - 20)));
		drawVSep(recti(pos2di(botRight.x-154, topLeft.y+19), pos2di(botRight.x-147, topLeft.y+TB_HEIGHT - 20)));

		// Draw the tabs
		recti contentArea(topLeft + pos2di(0, TB_HEIGHT), botRight);
		if (listPanel.isVisible())
			drawList(ele, contentArea);
		else if (layoutPanel.isVisible())
			drawLayoutView(ele, contentArea);
		else if (settingsPanel.isVisible())
			drawSettings(ele, contentArea);
		else if (statsPanel.isVisible())
			drawStats(ele, contentArea);

		clearDrawClip();
	}

	void update(float time) {
		// Update the various tabs
		updateList(time);
		updateLayoutView(time);
		updateSettings(time);
		updateStats(time);
	}

	void switchTab(LayoutTab tab) {
		listTab.setPressed(tab == LT_List);
		layoutTab.setPressed(tab == LT_Layout);
		statsTab.setPressed(tab == LT_Stats);
		settingsTab.setPressed(tab == LT_Settings);

		listPanel.setVisible(tab == LT_List);
		layoutPanel.setVisible(tab == LT_Layout);
		statsPanel.setVisible(tab == LT_Stats);
		settingsPanel.setVisible(tab == LT_Settings);

		layoutStatsEle.setVisible(tab != LT_Settings);

		updateLayout();
	}

	EventReturn onMouseEvent(GuiElement@ ele, const MouseEvent& evt) {
		DragResizeEvent re = handleDragResize(ele, evt, drag, MIN_WIDTH, MIN_HEIGHT);
		if (re != RE_None) {
			if (re == RE_Resized)
				syncPosition(ele.getSize());
			return ER_Absorb;
		}
		return ER_Pass;
	}

	EventReturn onGUIEvent(GuiElement@ ele, const GUIEvent& evt) {
		if (evt.EventType == GEVT_Focus_Gained && evt.Caller.isAncestor(ele)) {
			ele.bringToFront();
			bindEscapeEvent(ele);
		}
		else if (evt.EventType == GEVT_Closed) {
			closeLayoutWindow(this);
			return ER_Absorb;
		}

		switch (evt.EventType) {
			case GEVT_EditBox_Enter_Pressed:
			case GEVT_Focus_Lost:
				if (evt.Caller is scale)
					updateLayout();
			break;
			case GEVT_Clicked:
			case GEVT_Right_Clicked:
				if (evt.Caller is listTab) {
					switchTab(LT_List);
				}
				else if (evt.Caller is layoutTab) {
					switchTab(LT_Layout);
				}
				else if (evt.Caller is statsTab) {
					switchTab(LT_Stats);
				}
				else if (evt.Caller is settingsTab) {
					switchTab(LT_Settings);
				}
				else if (evt.Caller is saveButton) {
					if (saveLayout()) {
						if (!shiftKey)
							clearLayout();
					}
				}
				else if (evt.Caller is clearButton) {
					clearLayout();
				}
				else if (evt.Caller is exportButton) {
					if (exportLayout()) {
						playSound("confirm");
						addMessageDialog(localize("#LE_ExportLayout"), localize("#LE_ExportOK"), null);
					}
					else {
						playSound("deny");
						addMessageDialog(localize("#LE_ExportLayout"), localize("#LE_ExportFail"), null);
					}
				}
				else if (evt.Caller is importButton) {
					if (shiftKey) {
						importAll(ctrlKey);
					}
					else {
						MultiImportDialog@ dialog
							= addMultiImportDialog(localize("#LE_ImportTitle"),
									localize("#LE_ImportText"), null,
									"Layouts", ImportCallback(this));
						dialog.ok.setToolTip(localize("#LETT_ImportNow"));
					}
				}
				else if (evt.Caller is pickScaleButton) {
					ListSelectionDialog@ dialog = addListSelectionDialog(localize("#LE_PickScale"), null, ScaleCallback(this));

					for (uint i = 0; i < scaleValues.length(); ++i)
						dialog.addItem(localize(scaleNames[i])+": "+ftos_nice(scaleValues[i]));
				}
				else if (evt.Caller is close) {
					closeLayoutWindow(this);
					return ER_Absorb;
				}
			break;
		}

		if (listPanel.isVisible())
			return onListEvent(ele, evt);
		else if (layoutPanel.isVisible())
			return onLayoutViewEvent(ele, evt);
		else if (settingsPanel.isVisible())
			return onSettingsEvent(ele, evt);
		else if (statsPanel.isVisible())
			return onStatsEvent(ele, evt);
		return ER_Pass;
	}

	EventReturn onKeyEvent(GuiElement@ ele, const KeyEvent& evt) {
		return ER_Pass;
	}

	void importAll(bool override) {
		string@ folder = "Layouts";
		XMLList@ list = XMLList(folder);
		for (uint i = 0; i < list.getFileCount(); ++i) {
			string@ filename = list.getFileName(i);
			filename = filename.substr(folder.length()+1, filename.length()-folder.length()-5);

			import_layout(this, filename);

			if (!override) {
				string@ layName = hullEscape(name.getText());
				const HullLayout@ lay = getActiveEmpire().getShipLayout(layName);

				if (lay !is null)
					continue;
			}

			if (!hasHardError)
				saveLayout();
		}

		clearLayout();
		playSound("confirm");
	}

	/* }}} */
	/* {{{ Layout Handling */
	void clearLayout() {
		// Clear top bar data
		name.setText("");
		scale.setText("1");

		// Clear quick stats
		accelValue.setText("0.00");
		flightValue.setText("N/A");

		// Clear cost
		costTop.update(0, 0);
		costTop.update(1, 0);

		costBottom.update(0, 0);
		costBottom.update(1, 0);

		// Clear all stored systems
		for(uint i = 0; i < subSystems.length(); ++i)
			subSystems[i].remove();
		subSystems.resize(0);

		// Clear all sub system icons
		for (uint i = 0; i < subSystemIcons.length(); ++i)
			subSystemIcons[i].update();
		subSystemIcons.resize(0);

		clearError();

		// Notify the tabs of the clear
		listSelectLayout(null);
		layoutViewSelectLayout(null);
		settingsSelectLayout(null);
		statsSelectLayout(null);

		subSystemAccordion.switchTo(0);
		subSystemAccordion.updatePosition();
	}

	void addSubSystem(subSysEntry@ subSys, int num) {
		@subSystems[num] = subSys;
		@subSystemIcons[num] = subSysIcon(subSys, this, shipCircle);
	}

	void addSubSystem(subSysEntry@ subSys) {
		uint n = subSystems.length();
		subSystems.resize(n+1);
		subSystemIcons.resize(n+1);

		addSubSystem(subSys, n);
	}

	void addSubSystem(uint SubSysID, float scale, const pos2df &in position) {
		addSubSystem(subSysEntry(SubSysID, scale, position));
	}

	void addSubSystem(const subSystemDef@ def) {
		pos2df sysPos(0, 0);

		if (def.hasTag(tagHull)) {
			for (uint i = 0; i < subSystems.length(); ++i) {
				if (subSystems[i].hasTag(tagHull)) {
					subSystems[i].remove();
					sysPos = subSystems[i].position;
					break;
				}
			}
		}

		addSubSystem(subSysEntry(def.ID, 1.f, sysPos));
	}

	void addQueuedLink(int primary, int secondary) {
		QueuedLink@ link = QueuedLink();
		link.primary = primary;
		link.secondary = secondary;

		uint n = queuedLinks.length();
		queuedLinks.resize(n+1);
		@queuedLinks[n] = link;
	}

	void handleQueuedLinks() {
		uint lnks = queuedLinks.length();
		for (uint i = 0; i < lnks; ++i) {
			QueuedLink@ link = queuedLinks[i];
			if (link.primary < 0 || link.secondary >= int(subSystems.length()))
				continue;

			@subSystems[link.primary].linksTo = subSystems[link.secondary];
			@subSystems[link.secondary].linksTo = subSystems[link.primary];
		}
		queuedLinks.resize(0);
	}

	subSysDragger@ draggingSys;
	void dragNewSystem(const subSystemDef@ def) {
		dragNewSystem(def, 1.f, pos2di());
	}

	void dragNewSystem(const subSystemDef@ def, float scale) {
		dragNewSystem(def, scale, pos2di());
	}

	void dragNewSystem(const subSystemDef@ def, float scale, pos2di offset) {
		@draggingSys = subSysDragger(def, scale, this, null);
		drag.dragging = false;
		updateLayout();
	}

	void dropNewSystem() {
		if (draggingSys is null)
			return;

		pos2df layPos = draggingSys.getBlueprintPosition();
		if (makeDropPosition(layPos, draggingSys.scale, sqrt(draggingSys.scale))) {
			subSysEntry@ entry = subSysEntry(draggingSys.def.ID, draggingSys.scale, layPos);

			if (draggingSys.def.hasTag(tagHull)) {
				for (uint i = 0; i < subSystems.length(); ++i)
					if (subSystems[i].hasTag(tagHull))
						subSystems[i].remove();
			}

			addSubSystem(entry);
			updateLayout();
		}

		draggingSys.dragger.remove();
		@draggingSys.dragger = null;
		@draggingSys = null;

		drag.dragging = false;
		setGuiFocus(layoutPanel);
		updateLayout();
	}

	subSysIcon@ ghostedIcon;
	void ghostDragSystem(subSysIcon@ icon) {
		@ghostedIcon = icon;

		@draggingSys = subSysDragger(icon.entry, this, null);
		drag.dragging = false;
	}

	void dropGhostSystem(bool stillDragging) {
		// Delete when dropped back onto the list
		pos2di mousePos = getMousePosition();
		if (subSystemAccordion.getAbsolutePosition().isPointInside(mousePos)) {
			if (ghostedIcon !is null)
				ghostedIcon.entry.remove();
		}

		// Remove ghost dragger
		if (draggingSys !is null) {
			draggingSys.dragger.remove();
			@draggingSys.dragger = null;
			@draggingSys = null;
		}

		// Reset system
		if (ghostedIcon !is null) {
			setGuiFocus(ghostedIcon.dragger);
			ghostedIcon.dragging = stillDragging;
			@ghostedIcon = null;
		}

		drag.dragging = false;
	}

	void selectLayout(const HullLayout@ layout) {
		// Clear everything first
		clearLayout();

		// Update top bar information
		name.setText(layout.getName());
		scale.setText(ftos_nice(layout.scale * layout.scale, 3));

		// Add all sub systems
		uint count = layout.getSubSysCnt();
		subSystems.resize(count);
		subSystemIcons.resize(count);

		for(uint i = 0; i < count; ++i) {
			const subSystem@ sys = layout.getSubSys(i);
			subSysEntry@ entry = subSysEntry(sys.type.ID, sys.scale, layout.getSubSysPos(i));
			addSubSystem(entry, i);
		}

		// Load linked systems
		for (int i = 0; i < int(count); ++i) {
			int linkTo = layout.getSubSysLink(i);
			if (linkTo < 0 || linkTo >= int(count))
				continue;

			@subSystems[i].linksTo = subSystems[linkTo];
			@subSystems[linkTo].linksTo = subSystems[i];
		}

		// Notify the tabs the layout has switched
		listSelectLayout(layout);
		settingsSelectLayout(layout);

		// Update the layout
		updateLayout();
	}

	const HullLayout@ constructTempHull() {
		Empire@ emp = getActiveEmpire();
		uint sysCnt = subSystems.length();

		if (sysCnt == 0)
			return null;

		// Build the layout
		// * Check which systems link to which
		for(uint i = 0; i < sysCnt; ++i) {
			subSysEntry@ entry = subSystems[i];
			if(!entry.checkExists())
				continue;
			entry.updateCollision(subSystems);
		}

		// * Add systems to the temp hull
		for(uint i = 0; i < sysCnt; ++i) {
			subSysEntry@ entry = subSystems[i];
			if(!entry.checkExists())
				continue;
			const subSystemDef@ sys = getSubSystemDefByID(entry.sysID);
			addSubSysToTempHull(sys, entry.scale, entry.position, entry.getCollision(subSystems));
		}

		// Check if we should add our dragging system
		if (draggingSys !is null && ghostedIcon is null) {
			addSubSysToTempHull(draggingSys.def, draggingSys.scale, pos2df(), -1);
		}

		const HullLayout@ tempHull = finalizeTempHull(s_to_f(scale.getText()));

		if (tempHull !is null) {
			applySettingsToTempHull();
			applySettingsToHull(tempHull);
		}

		return tempHull;
	}

	void destroyTempHull(const HullLayout@ hull) {
		freeTempHull();
	}

	bool exportLayout() {
		Empire@ emp = getActiveEmpire();
		const HullLayout@ layout = constructTempHull();

		if (layout is null)
			return false;


		string@ shipName = hullEscape(name.getText());
		bool success = export_layout(layout, shipName, order_customizer.hasChanges);
		destroyTempHull(layout);

		return success;
	}

	void updateLayout() {
		Empire@ emp = getActiveEmpire();
		const HullLayout@ layout = constructTempHull();

		if (layout is null) {
			// Error handling
			setError(getTempHullError(), true, true);

			// Set space
			float used = 0.f, total = 0.f;
			getTempHullSpace(used, total);
			setSpace(used, total);

			// Notify the tabs of the update
			listUpdateLayout(null, null);
			layoutViewUpdateLayout(null, null);
			statsUpdateLayout(null, null);
			settingsUpdateLayout(null, null);
			return;
		}

		// Retrieve stats for the layout
		HullStats@ stats = layout.getStats();
		@lastStats = stats;

		// Update quick stats
		// * Acceleration
		float mass = stats.getHint("Mass"), thrust = stats.getHint("Thrust");
		if(mass > 0 && thrust > 0)
			accelValue.setText(ftos_nice(thrust/mass/unitsPerAU, 4) + localize("#LE_AUpss"));
		else
			accelValue.setText("0.00");

		// * Flight time
		float fuel = stats.getHint("Fuel"), fuelUse = stats.getHint("FuelUse");
		if(fuel > 0 && fuelUse < 0)
			flightValue.setText(secondsToTime(int(fuel / -fuelUse)));
		else if(fuelUse < 0)
			flightValue.setText(localize("#LEE_Dead"));
		else
			flightValue.setText(localize("#LE_NA"));

		// Update cost
		costTop.update(0, stats.getCost("AdvParts"));
		costTop.update(1, stats.getCost("Metals"));
		costBottom.update(0, stats.getCost("Electronics"));
		costBottom.update(1, stats.getCost("Labr"));

		// Set space
		setSpace(stats.spaceTaken, stats.spaceTotal);

		// Warning handling
		if(stats.getHint("Control") < 0)
			setError(localize("#LEE_Control"), true, false);
		else if(stats.getHint("Air") < 0)
			setError(localize("#LEE_LifeSupport"), true, false);
		else if(stats.getHint("Crew") < 0)
			setError(localize("#LEE_Crew"), true, false);
		else if(stats.getHint("FuelUse") < 0 && stats.getHint("Fuel") <= 0)
			setError(localize("#LEE_Fuel"), true, false);
		else if(stats.getHint("Power") < 0)
			setError(localize("#LEE_Power"), false, false);
		else if(stats.getHint("Charge") <= 0 && stats.getHint("Power") != 0)
			setError(localize("#LEE_Charge"), true, false);
		else if (stats.getHint("FuelUse") < 0 && (stats.getHint("Fuel")/stats.getHint("FuelUse")) > -60 * 5)
			setError(localize("#LEE_FlightTime"), false, false);
		else if(stats.getHint("Thrust") <= 0 && !layout.hasSystemWithTag("Station"))
			setError(localize("#LEE_Thrust"), false, false);
		else if(layout.hasSystemWithTag("UsesCargo") && stats.getHint("Cargo") <= 0)
			setError(localize("#LEE_Cargo"), false, false);
		else
			clearError();

		// Notify the tabs of the update
		listUpdateLayout(layout, stats);
		layoutViewUpdateLayout(layout, stats);
		statsUpdateLayout(layout, stats);
		settingsUpdateLayout(layout, stats);

		// Clean up
		destroyTempHull(layout);
	}

	bool saveLayout() {
		if (hasHardError)
			return false;

		uint sysCnt = subSystems.length();
		if (sysCnt == 0)
			return false;

		float shipScale = s_to_f(scale.getText());
		string@ shipName = hullEscape(name.getText());

		if (shipName is null)
			return false;

		Empire@ emp = getActiveEmpire();

		clearActiveHull();
		setActiveHullScale(shipScale);

		// Build the layout
		// * Check which systems link to which
		for(uint i = 0; i < sysCnt; ++i) {
			subSysEntry@ entry = subSystems[i];
			if(!entry.checkExists())
				continue;
			entry.updateCollision(subSystems);
		}

		// * Add systems to the active hull
		for(uint i = 0; i < sysCnt; ++i) {
			subSysEntry@ entry = subSystems[i];
			if(!entry.checkExists())
				continue;
			const subSystemDef@ sys = getSubSystemDefByID(entry.sysID);
			addSysToActiveHull(sys, entry.scale, entry.position, entry.getCollision(subSystems));
		}

		applySettingsToActiveHull();

		if (finalizeActiveHull(shipName)) {
			const HullLayout@ layout = getActiveEmpire().getShipLayout(shipName);
			if (layout !is null)
				applySettingsToHull(layout);
			return true;
		}
		else {
			setError(localize("#LEE_Unique"), true, true);
			return false;
		}
	}

	void setError(string@ msg, bool isError, bool isHard) {
		@error = msg;
		hasError = isError;
		hasHardError = isHard;
	}

	void clearError() {
		@error = null;
		hasError = false;
		hasHardError = false;
	}

	void setSpace(float used, float total) {
		usedSpace = used;
		maxSpace = total;
	}

	void setScale(float newScale) {
		scale.setText(ftos_nice(newScale, 3));
	}
	
	void setName(string@ newName) {
		name.setText(newName);
	}
	/* }}} */
	/* {{{ Blueprints list tab */
	GuiListBox@ layoutList;
	uint prevBlueprintCount;
	const HullLayout@ selectedLayout;
	bool selecting;

	SortedBlueprintList blueprints;

	GuiComboBox@ sortMode;
	GuiButton@ showObsolete;
	GuiButton@ obsoleteAll;
	GuiButton@ updateAll;

	GuiStaticText@ layoutName;
	GuiButton@ obsoleteButton;
	GuiButton@ updateButton;

	GuiStaticText@ thresholdText;
	GuiStaticText@ thresholdLabel;
	GuiEditBox@ updateThreshold;

	LayoutViewer@ quickLayoutView;

	void initList(GuiPanel@ ele) {
		@layoutList = GuiListBox(recti(6, 6, 100, 100), true, ele);

		@sortMode = GuiComboBox(recti(0, 0, 113, 20), ele);
		sortMode.addItem("-- "+localize("#asc")+" --");
		sortMode.addItem(localize("#LET_SortName"));
		sortMode.addItem(localize("#LET_SortScale"));

		sortMode.addItem("-- "+localize("#desc")+" --");
		sortMode.addItem(localize("#LET_SortName"));
		sortMode.addItem(localize("#LET_SortScale"));
		sortMode.setSelected(2);

		@showObsolete = ToggleButton(false, dim2di(112, 20), localize("#LET_ShowObsolete"), ele);
		@updateAll = Button(dim2di(113, 20), localize("#LET_UpdateAll"), ele);
		@obsoleteAll = Button(dim2di(112, 20), localize("#LET_ObsoleteAll"), ele);

		@layoutName = GuiStaticText(recti(248, 9, 300, 30), null, false, false, false, ele);
		layoutName.setFont("stroked_subtitle");

		@updateButton = Button(recti(248, 40, 348, 60), localize("#LET_UpdateHull"), ele);
		@obsoleteButton = Button(recti(353, 40, 453, 60), localize("#LET_Make_Obs"), ele);

		@thresholdText = GuiStaticText(recti(pos2di(250, 65), dim2di(130, 18)), localize("#LET_AutoUp"), false, false, false, ele);
		@updateThreshold = GuiEditBox(recti(pos2di(355, 65), dim2di(50, 18)), "10", true, ele);
		@thresholdLabel = GuiStaticText(recti(pos2di(410, 65), dim2di(200, 18)), localize("#LET_TechLevels"), false, false, false, ele);

		@quickLayoutView = LayoutViewer(recti(pos2di(248, 120), dim2di(340, int(340.f*0.83268f))), ele);

		prevBlueprintCount = 0;
		selecting = false;
	}
	
	void syncListPosition(dim2di size) {
		layoutList.setSize(dim2di(226, size.height - 63));

		sortMode.setPosition(pos2di(7, size.height - 52));
		showObsolete.setPosition(pos2di(120, size.height - 52));

		updateAll.setPosition(pos2di(7, size.height - 27));
		obsoleteAll.setPosition(pos2di(120, size.height - 27));

		layoutName.setSize(dim2di(size.width - 271 - 248, 20));
	}

	void updateLayoutList() {
		// Get the currently selected layout
		int sel = layoutList.getSelected();
		string@ selLayout = "";

		if (uint(sel) < blueprints.length())
			selLayout = blueprints.getName(sel);

		// Get current sort mode
		bool showObs = showObsolete.isPressed();
		BlueprintSortMode mode = BSM_Scale;
		bool asc = true;
		
		int selSort = sortMode.getSelected();
		if (selSort != -1) {
			int selMode = (selSort % 3) - 1;
			if (selMode < 0)
				selMode = 0;

			mode = BlueprintSortMode(selMode);
			asc = selSort < 3;
		}

		Empire@ emp = getActiveEmpire();
		sel = -1;

		// Update layouts
		blueprints.setShowObsolete(showObs);
		blueprints.setSortMode(mode, asc);
		blueprints.update(emp, true);

		// Fill the listbox
		layoutList.clear();
		uint layCnt = blueprints.length();
		prevBlueprintCount = emp.getShipLayoutCnt();
		for (uint i = 0; i < layCnt; ++i) {
			layoutList.addItem(blueprints.getText(i));

			if (blueprints.getLayout(i).obsolete)
				layoutList.setItemOverrideColor(i, Color(0xffff8080));

			if (blueprints.getName(i) == selLayout)
				sel = i;
		}

		layoutList.setSelected(sel);
	}

	const HullLayout@ getListSelectedLayout() {
		uint sel = layoutList.getSelected();
		if (sel < blueprints.length())
			return blueprints.getLayout(sel);
		return null;
	}

	void updateList(float time) {
		// Update blueprints list if the amount changes
		uint layCnt = getActiveEmpire().getShipLayoutCnt();
		if (layCnt != prevBlueprintCount)
			updateLayoutList();
	}

	void listSelectLayout(const HullLayout@ layout) {
		if (selecting && layout is null) {
			selecting = false;
			return;
		}

		if (layout !is selectedLayout || layout is null) {
			@selectedLayout = null;
			layoutList.setSelected(-1);

			layoutName.setText(null);
			quickLayoutView.setLayout(null);
			updateThreshold.setText("10");
			updateThreshold.setEnabled(false);
			updateButton.setEnabled(false);
			obsoleteButton.setEnabled(false);
			obsoleteButton.setText(localize("#LET_Make_Obs"));

			return;
		}

		layoutName.setText(layout.getName());
		quickLayoutView.setLayout(layout);
		updateThreshold.setEnabled(true);
		updateThreshold.setText(f_to_s(layout.updateThreshold, 0));
		updateButton.setEnabled(true);
		obsoleteButton.setEnabled(true);

		if (layout.obsolete) {
			obsoleteButton.setText(localize("#LET_Unmake_Obs"));
			layoutName.setColor(Color(255, 255, 128, 128));
		}
		else {
			obsoleteButton.setText(localize("#LET_Make_Obs"));
			layoutName.setColor(Color(255, 255, 255, 255));
		}
	}

	void listUpdateLayout(const HullLayout@ layout, HullStats@ stats) {
	}

	void drawList(GuiElement@ ele, recti pos) {
		pos2di topLeft = pos.UpperLeftCorner;
		pos2di botRight = pos.LowerRightCorner;
		dim2di size = pos.getSize();

		drawVSep(recti(topLeft + pos2di(231, 6), dim2di(7, size.height - 12)));
		drawHSep(recti(pos2di(topLeft.x + 6, botRight.y - 59), dim2di(227, 7)));
		drawHSep(recti(pos2di(topLeft.x + 6, botRight.y - 34), dim2di(227, 7)));

		drawLightArea(recti(topLeft + pos2di(238, 93), botRight - pos2di(270, 7)));
		drawVSep(recti(pos2di(botRight.x-271, topLeft.y+6), dim2di(7, size.height - 12)));

		drawDarkArea(recti(pos2di(topLeft.x + 238, topLeft.y + 7), pos2di(botRight.x - 270, topLeft.y + 31)));
		drawHSep(recti(pos2di(topLeft.x + 237, topLeft.y + 30), pos2di(botRight.x - 269, topLeft.y + 37)));

		drawDarkArea(recti(pos2di(topLeft.x + 238, topLeft.y + 37), pos2di(botRight.x - 270, topLeft.y + 87)));
		drawHSep(recti(pos2di(topLeft.x + 237, topLeft.y + 86), pos2di(botRight.x - 269, topLeft.y + 93)));

		drawRect(recti(pos2di(botRight.x - 265, topLeft.y + 7), pos2di(botRight.x - 7, botRight.y - 7)), Color(0xff000000));
	}

	EventReturn onListEvent(GuiElement@ ele, const GUIEvent& evt) {
		switch (evt.EventType) {
			case GEVT_Clicked: {
				Empire@ emp = getActiveEmpire();

				if (selectedLayout !is null) {
					if (evt.Caller is updateButton) {
						if (!selectedLayout.obsolete)
							emp.updateHull(selectedLayout.getName(), 0.01f);
						updateLayoutList();
						return ER_Pass;
					}
					else if (evt.Caller is obsoleteButton) {
						emp.toggleObsolete(selectedLayout.getName());
						updateLayoutList();

						if (selectedLayout.obsolete) {
							obsoleteButton.setText(localize("#LET_Unmake_Obs"));
							layoutName.setColor(Color(255, 255, 128, 128));
						}
						else {
							obsoleteButton.setText(localize("#LET_Make_Obs"));
							layoutName.setColor(Color(255, 255, 255, 255));
						}
						return ER_Pass;
					}
				}

				if (evt.Caller is updateAll) {
					uint cnt = emp.getShipLayoutCnt();
					for (uint i = 0; i < cnt; ++i) {
						const HullLayout@ lay = emp.getShipLayout(i);
						if (!lay.obsolete)
							emp.updateHull(lay.getName(), 0.01f);
					}
					updateLayoutList();
				}
				else if (evt.Caller is obsoleteAll) {
					uint cnt = emp.getShipLayoutCnt();
					for (uint i = 0; i < cnt; ++i) {
						const HullLayout@ lay = emp.getShipLayout(i);
						if (!lay.obsolete)
							emp.toggleObsolete(lay.getName());
					}
					updateLayoutList();
				}
				else if (evt.Caller is showObsolete) {
					updateLayoutList();
				}
		    } break;
			case GEVT_ComboBox_Changed:
				if (evt.Caller is sortMode)
					updateLayoutList();
			break;
			case GEVT_EditBox_Changed:
			case GEVT_EditBox_Enter_Pressed:
				if (evt.Caller is updateThreshold) {
					if (selectedLayout !is null) {
						selectedLayout.updateThreshold = s_to_f(updateThreshold.getText());
						return ER_Pass;
					}
				}
			break;
			case GEVT_Listbox_Changed:
				if (evt.Caller is layoutList) {
					const HullLayout@ lay = getListSelectedLayout();
					if (lay !is null) {
						@selectedLayout = lay;
						selecting = true;
						selectLayout(lay);
					}
					return ER_Absorb;
				}
			break;
			case GEVT_Listbox_Selected_Again:
				if (evt.Caller is layoutList) {
					switchTab(LT_Layout);
					return ER_Absorb;
				}
			break;
		}

		return ER_Pass;
	}
	/* }}} */
	/* {{{ Layout tab */
	GuiPanel@ shipCircle;
	GuiImage@ circleFront;
	subSysIcon@[] subSystemIcons;

	GuiPanel@ subSysDeltaPanel;
	GuiExtText@ subSysDeltaInfo;

	GuiPanel@ sysInfoPanel;
	GuiImage@ sysImg;
	GuiExtText@ sysTitle;
	ResourceGrid@ sysCost;
	GuiExtText@ sysDesc;

	GuiPanel@ statsTooltip;
	GuiExtText@ statsTooltipText;

	GuiScripted@ layoutStatsEle;
	layout_stats@ layoutStats;

	GuiStaticText@ hullSpace;
	GuiExtText@ sysHoverName;

	GuiStaticText@ errorBox;
	GuiImage@ errorBoxIcon;

	GuiButton@ bothModeButton;
	GuiButton@ iconModeButton;
	GuiButton@ textModeButton;

	subSysList@[] subSystemLists;
	Accordion@ subSystemAccordion;

	float curNegStat;
	float curPosStat;
	int prevHoveredStat;

	uint lastSysCount;
	int hoveredSubSystemID;
	float layoutSizeFactor;

	void addList(string@ text, string@ tag1, string@ tag2, GuiElement@ ele) {
		uint n = subSystemLists.length();
		subSystemLists.resize(n+1);

		@subSystemLists[n] = subSysList(this, ele);
		if (tag1 !is null)
			subSystemLists[n].addTag(tag1);
		if (tag2 !is null)
			subSystemLists[n].addTag(tag2);

		subSystemAccordion.add(text, subSystemLists[n].ele);
	}

	void initLayoutView(GuiPanel@ ele) {
		@shipCircle = GuiPanel(recti(), false, SBM_Invisible, SBM_Invisible, ele);
		lastSysCount = 0;

		@circleFront = GuiImage(pos2di(184, 7), "layout_ship_circle_front", ele);

		@layoutStats = layout_stats();
		@layoutStatsEle = GuiScripted(recti(0, 0, 200, 200), layoutStats, ele.getParent());
		layoutStats.init(layoutStatsEle);

		curNegStat = 0;
		curPosStat = 0;
		prevHoveredStat = -1;
		hoveredSubSystemID = 0;

		// Create the accordion
		@subSystemAccordion = Accordion(recti(), 20, ele);

		// Lists of sub systems
		addList(localize("#LE_Hulls"), "Hull", null, ele);
		addList(localize("#LE_Control"), "Control", null, ele);
		addList(localize("#LE_Support"), "Support", null, ele);
		addList(localize("#LE_Engines"), "Engine", null, ele);
		addList(localize("#LE_DefenseArmor"), "Defense", "Armor", ele);
		addList(localize("#LE_Weapons"), "Weapon", null, ele);
		addList(localize("#LE_SubSystemModifiers"), "Link", null, ele);
		addList(localize("#LE_Misc"), null, null, ele);

		subSystemAccordion.switchTo(0);

		// Hull used space
		@hullSpace = GuiStaticText(recti(188, 11, 350, 28), localize("#LE_Space")+": 0/0", false, false, false, ele);

		// Mode switch buttons
		@bothModeButton = ToggleButton(true, recti(), localize("#LE_Both"), ele);
		@iconModeButton = ToggleButton(false, recti(), localize("#LE_Icons"), ele);
		@textModeButton = ToggleButton(false, recti(), localize("#LE_Text"), ele);

		// Sub System Hover Information
		@sysInfoPanel = GuiPanel( recti(pos2di(183, 7), dim2di(365, 473)), true, SBM_Auto, SBM_Invisible, ele);
		sysInfoPanel.setOverrideColor(Color(0xff000000));
		sysInfoPanel.setVisible(false);
		
		@sysImg = GuiImage(pos2di(2,2), "GenericSubSys", sysInfoPanel);
		sysImg.setScaleImage(true);
		sysImg.setSize(dim2di(64,64));

		@sysTitle = GuiExtText(recti(70, 5, 600-4, 473), sysInfoPanel);

		@sysCost = ResourceGrid(sysInfoPanel, pos2di(70, 44), dim2di(70, 17), 4);
		sysCost.addDefaults(true);
		
		@sysDesc = GuiExtText(recti(8, 68, 600-8, 473), sysInfoPanel);
		sysDesc.setShadow(Color(255,0,0,0));
		sysDesc.setText("#tab:66#"+localize("#LET_SelectForDesc"));
		
		sysInfoPanel.fitChildren();

		// Error message display
		@errorBox = GuiStaticText(recti(), null, false, false, false, ele);
		errorBox.setColor(Color(255,255,20,20));
		errorBox.setVisible(false);
		
		@errorBoxIcon = GuiImage(pos2di(1, 1), "layout_error", errorBox);

		// Stat breakdown
		@statsTooltip = GuiPanel(recti(0, 0, 300, 200), true, SBM_Invisible, SBM_Invisible, null);
		@statsTooltipText = GuiExtText(recti(4, 4, 292, 192), statsTooltip);

		statsTooltip.setOverrideColor(Color(255, 0, 0, 0));
		statsTooltip.setVisible(false);

		// SubSystemDelta panel
		@subSysDeltaPanel = GuiPanel(recti(pos2di(7, 7), dim2di(210, 100)), true, SBM_Invisible, SBM_Invisible, ele);
		subSysDeltaPanel.setOverrideColor(Color(0xff000000));
		subSysDeltaPanel.setVisible(false);	

		@subSysDeltaInfo = GuiExtText(recti(4, 4, 202, 100), subSysDeltaPanel);
		subSysDeltaPanel.fitChildren();

		// System hover name
		@sysHoverName = GuiExtText(recti(), null);
	}
	
	void syncLayoutViewPosition(dim2di size) {
		int listWidth = min(MAX_SYSLIST_WIDTH, size.width - 932 + 170);

		subSysDeltaPanel.setSize(dim2di(listWidth, size.height - 14));

		errorBox.setPosition(pos2di(size.width - 265, 17));
		errorBox.setSize(dim2di(265, 27));

		subSystemAccordion.setPosition(pos2di(7, 7));
		subSystemAccordion.setSize(dim2di(listWidth, size.height - 39));
		subSystemAccordion.syncPosition();

		sysInfoPanel.setPosition(pos2di(listWidth + 13, 7));
		sysInfoPanel.setSize(dim2di(sysInfoPanel.getSize().width, size.height - 14));

		int buttonWidth = ceil(float(listWidth) / 3.f);

		bothModeButton.setPosition(pos2di(7, size.height - 27));
		bothModeButton.setSize(dim2di(buttonWidth, 20));

		iconModeButton.setPosition(pos2di(7+buttonWidth, size.height - 27));
		iconModeButton.setSize(dim2di(buttonWidth, 20));

		textModeButton.setPosition(pos2di(7+2*buttonWidth, size.height - 27));
		textModeButton.setSize(dim2di(buttonWidth, 20));

		hullSpace.setPosition(pos2di(listWidth+18, 11));

		int widthArea = size.width - listWidth - 21 - 264 - 44;
		int heightArea = size.height - 14;
		int circleSize = min(widthArea, heightArea);
		if (circleSize < 440)
			circleSize = 428;

		shipCircle.setPosition(pos2di(listWidth + 14 + (widthArea - circleSize) / 2,
									  7 + (heightArea - circleSize) / 2));
		shipCircle.setSize(dim2di(circleSize, circleSize));

		layoutSizeFactor = circleSize / 428.f;

		for(uint i = 0; i < subSystemIcons.length(); ++i) {
			subSystemIcons[i].updatePosition();
			subSystemIcons[i].syncScale();
		}

		circleFront.setPosition(pos2di(size.width - 264 - 55,
						(size.height - 428) / 2));
	}

	// Assumption: Systems are never removed from the available list.
	// If they are, this will need to be changed.
	void updateSubSystemLists() {
		const Empire@ emp = getActiveEmpire();
		uint sysCount = emp.getSubSysDataCnt();

		// Add new systems
		for (uint i = 0; i < sysCount; ++i) {
			const subSystemDef@ def = emp.getSubSysData(i).type;

			if (def.hasTag(tagStructure))
				continue;

			for (uint j = 0; j < subSystemLists.length(); ++j)
				if (subSystemLists[j].add(def))
					break;
		}
	}

	void updateLayoutView(float time) {
		// Check if we should update the parts lists
		const Empire@ emp = getActiveEmpire();
		uint sysCount = emp.getSubSysDataCnt();

		if (sysCount != lastSysCount) {
			updateSubSystemLists();
			lastSysCount = sysCount;
		}

		// Check lists for scroll
		for (uint j = 0; j < subSystemLists.length(); ++j) {
			if (subSystemLists[j].ele.isVisible()) {
				subSystemLists[j].checkScroll();

				if (subSystemAccordion.elements[j].animating)
					subSystemLists[j].scroll.setVisible(false);
			}
			else {
				subSystemLists[j].selected = -1;
			}
		}

		// Animate accordion
		subSystemAccordion.animate(time);

		// Check sub systems for removal
		bool subSysChanged = false;
		for(uint i = 0; i < subSystems.length(); ++i) {
			if(!subSystems[i].checkExists()) {
				subSystems.erase(i); --i;
				subSysChanged = true;
			}
		}

		if(subSysChanged)
			updateLayout();
		
		// Update the visual systems
		for(uint i = 0; i < subSystemIcons.length(); ++i)
			if(subSystemIcons[i].update())
				subSystemIcons.erase(i--);

		// Update hover name
		if (layoutPanel.isVisible()) {
			bool hasHover = false;

			for (uint i = 0; i < subSystemIcons.length(); ++i) {
				subSysIcon@ icon = subSystemIcons[i];

				if (icon.entry.hovered) {
					hasHover = true;

					pos2di pos = icon.dragger.getAbsolutePosition().UpperLeftCorner - pos2di(100, 34);
					if (pos.y < 0)
						pos.y += 34 + icon.dragger.getSize().height;
					sysHoverName.setPosition(pos);
					sysHoverName.setSize(dim2di(200+icon.dragger.getSize().width, 34));
					sysHoverName.setText(icon.hoverText);
					sysHoverName.setVisible(true);
					sysHoverName.bringToFront();
					break;
				}
			}

			if (!hasHover)
				sysHoverName.setVisible(false);
		}

		// Update the stat overlay on the systems
		updateStatBreakdown();
	}

	void layoutViewSelectLayout(const HullLayout@ layout) {
		layoutStats.clear();
	}

	void layoutViewUpdateLayout(const HullLayout@ layout, HullStats@ stats) {
		// Update statistics
		if (stats !is null)
			layoutStats.syncToStats(stats);

		// Update space
		if (maxSpace > 0) {
			hullSpace.setText(localize("#LE_Space")+": " + f_to_s(usedSpace, 2) + "/" + f_to_s(maxSpace, 2));

			if (maxSpace >= usedSpace)
				hullSpace.setColor(Color(255, 255, 255, 255));
			else
				hullSpace.setColor(Color(255, 255, 20, 20));
		}
		else {
			hullSpace.setText("Space: ?/?");
			hullSpace.setColor(Color(255, 255, 255, 255));
		}

		// Update error
		if (error !is null) {
			errorBox.setVisible(true);
			errorBox.setText("        " + error);
			errorBoxIcon.setImage(hasError ? "layout_error" : "layout_warning");
		}
		else {
			errorBox.setVisible(false);
		}
	}

	void drawLayoutView(GuiElement@ ele, recti pos) {
		pos2di topLeft = pos.UpperLeftCorner;
		pos2di botRight = pos.LowerRightCorner;
		dim2di size = pos.getSize();

		int listWidth = min(MAX_SYSLIST_WIDTH, size.width - 932 + 170);

		drawDarkArea(recti(topLeft + pos2di(7, 7), dim2di(listWidth, size.height - 14)));
		drawVSep(recti(topLeft + pos2di(listWidth + 6, 6), dim2di(7, size.height - 12)));
		drawHSep(recti(pos2di(topLeft.x + 6, botRight.y - 34), dim2di(listWidth + 2, 7)));
		drawLightArea(recti(topLeft + pos2di(listWidth + 13, 7), botRight - pos2di(270, 7)));

		drawVSep(recti(pos2di(botRight.x - 271, topLeft.y + 6), dim2di(7, size.height - 12)));
		drawRect(recti(pos2di(botRight.x - 265, topLeft.y + 7), pos2di(botRight.x - 7, botRight.y - 7)), Color(0xff000000));

		recti circPos = shipCircle.getAbsolutePosition();
		const Texture@ circle;

		if (error !is null && hasError) {
			@circle = getMaterialTexture("layout_ship_circle_error");
		}
		else {
			@circle = getMaterialTexture("layout_ship_circle");
		}

		drawTexture(circle, circPos,
				recti(pos2di(0, 0), circle.get_size()),
				Color(0xffffffff), true);

		drawGrid(circPos, 16 * layoutSizeFactor, 1,
				Color(0), Color(0xffffffff));
	}

	EventReturn onLayoutViewEvent(GuiElement@ ele, const GUIEvent& evt) {
		switch (evt.EventType) {
			case GEVT_Clicked: {
				if (evt.Caller is bothModeButton || evt.Caller is textModeButton || evt.Caller is iconModeButton) {
					ListMode mode = LM_IconsText;

					if (evt.Caller is textModeButton)
						mode = LM_Text;
					else if (evt.Caller is iconModeButton)
						mode = LM_Icons;

					for (uint i = 0; i < subSystemLists.length(); ++i) {
						subSysList@ list = subSystemLists[i];
						if (list.mode != mode) {
							list.mode = mode;
							list.checkScroll();
						}
					}

					subSystemAccordion.syncPosition();
					bothModeButton.setPressed(mode == LM_IconsText);
					iconModeButton.setPressed(mode == LM_Icons);
					textModeButton.setPressed(mode == LM_Text);
					return ER_Absorb;
				}
		   } break;
		}
		return ER_Pass;
	}

	/* {{{ Sub System Delta Display */
	void hideSubSystemDelta() {
		subSysDeltaPanel.setVisible(false);
	}

	void showSubSystemDelta(const SubSystemComp &in original, const SubSystemComp &in replaceWith, DeltaMode mode) {
		float shipScale = s_to_f(scale.getText());

		SubSystemFactory@ replaceFact = replaceWith.createFactory(shipScale);	
		replaceFact.compare(original.createFactory(shipScale), false);
		
		uint count = replaceFact.hintDeltaCount;
		if(count == 0) {
			hideSubSystemDelta();
			return;
		}
		
		subSysDeltaPanel.setVisible(true);
		string@ deltaText = "";

		if (mode == DM_DeltaOnly)
			deltaText = combine("#font:subtitle#", replaceFact.active.type.getName(), "#font#\n");
		
		for(uint i = 0; i < count; ++i) {
			float delta = replaceFact.getHintDelta(i);
			if(delta == 0)
				continue;
			
			string@ hintName = replaceFact.getHintDeltaName(i);
			string@ hintNameTrue = localizeStatName(hintName, localeLayoutHint, false);
			
			if(mode == DM_DeltaOnly || hintNameTrue is null) {
				if(hintNameTrue is null)
					@hintNameTrue = localizeStatName(hintName, localeLayoutHint, true);
				deltaText += combine(" ", hintNameTrue, ( delta >= 0 ? ":#tab:120##c:green#" : ":#tab:120##c:red#-" ), standardize(abs(delta)), "#c#\n");
			}
			else if(mode == DM_PrevDeltaResult) {
				float prev = 0;
				if(@lastStats != null)
					prev = lastStats.getHint(hintName);
				deltaText += combine(combine(hintNameTrue, ":\n#tab:10#", standardizeAndColor(prev), (delta >= 0 ? "#tab:25##c:green#+ " : "#tab:25##c:red#- "), standardize(abs(delta))), "#c# => ", standardizeAndColor(prev + delta), "\n");
			}
		}
		
		subSysDeltaInfo.setText(deltaText);
	}

	void setAllButtonShows(GuiElement@ source) {
		if(source is null) {
			for(uint i = 0; i < subSystemIcons.length(); ++i)
				subSystemIcons[i].showButtons(false);
			hideSubSystemDelta();
		}
		else {
			for(uint i = 0; i < subSystemIcons.length(); ++i) {
				subSysIcon@ item = @subSystemIcons[i];
				bool isAncestor = source.isAncestor(item.dragger);
				item.showButtons( isAncestor );
				if(isAncestor) {
					int link = item.entry.getCollision(subSystems);
					int linkedID = -1;
					float linkedScale = 1.f;

					if (link != -1) {
						linkedID = int(subSystems[link].sysID);
						linkedScale = subSystems[link].scale;
					}

					if(@item.min != null && item.min is source)
						showSubSystemDelta(SubSystemComp(item.entry.sysID, item.entry.scale, linkedID, linkedScale), SubSystemComp(item.entry.sysID, shiftKey ? item.entry.scale - 0.25f : item.entry.scale / 2.f, linkedID, linkedScale), DM_PrevDeltaResult);
					else if(@item.plus != null && item.plus is source)
						showSubSystemDelta(SubSystemComp(item.entry.sysID, item.entry.scale, linkedID, linkedScale), SubSystemComp(item.entry.sysID, shiftKey ? item.entry.scale + 0.25f : item.entry.scale * 2.f, linkedID, linkedScale), DM_PrevDeltaResult);
					else if(item.x is source)
						showSubSystemDelta(SubSystemComp(item.entry.sysID, item.entry.scale, linkedID, linkedScale), SubSystemComp(), DM_PrevDeltaResult);
					else if(item.dragger is source)
						showSubSystemDelta(SubSystemComp(), SubSystemComp(item.entry.sysID, item.entry.scale, linkedID, linkedScale), DM_DeltaOnly);
					else
						hideSubSystemDelta();
				}
			}
		}
	}
	/* }}} */
	/* {{{ Stat Breakdown Display */
	void updateStatBreakdown() {
		if (drag.dragging || drag.resizing) {
			statsTooltip.setVisible(false);
			return;
		}

		if (layoutStats.hovered >= 0) {
			statsTooltip.setVisible(true);
			statsTooltip.bringToFront();
			anchorToMouse(statsTooltip);

			if (layoutStats.hovered != prevHoveredStat) {
				prevHoveredStat = layoutStats.hovered;
				lyt_stat_entry@ entry = layoutStats.stats[layoutStats.hovered];

				string@ text = combine("#font:title#", entry.name, "#font#");
				if (entry.tooltip !is null)
					text += "\n"+entry.tooltip;

				curNegStat = 0.f;
				curPosStat = 0.f;

				uint sysCnt = subSystems.length();
				SubSystemFactory@ fact = SubSystemFactory();
				fact.objectScale = s_to_f(scale.getText());

				for (uint i = 0; i < sysCnt; ++i) {
					subSysEntry@ sysEntry = subSystems[i];
					if (!sysEntry.checkExists())
						continue;
					sysEntry.generate(fact);
					if (fact.active is null)
						continue;

					const subSystem@ sys = fact.active;
					float val = 0;

					if (sys.hasHint(entry.stat))
						val = sys.getHint(entry.stat);
					else if (sys.hasRequire(entry.stat))
						val = -sys.getRequire(entry.stat);
					else if (sys.hasConsume(entry.stat))
						val = -sys.getConsume(entry.stat);
					else if (entry.stat == strHP)
						val = sys.maxHP;
					else if (entry.stat == strMass)
						val = sys.mass;

					sysEntry.statMod = val;

					if (val != 0) {
						float absVal = abs(val);
						if (absVal < 1)
							@sysEntry.statText = ftos_nice(absVal, 2);
						else if (absVal < 10)
							@sysEntry.statText = ftos_nice(absVal, 1);
						else if (absVal < 100)
							@sysEntry.statText = f_to_s(absVal, 0);
						else
							@sysEntry.statText = standardize(absVal);

						if (val > 0) {
							curPosStat += val;
						}
						else {
							sysEntry.statText = "-"+sysEntry.statText;
							curNegStat -= val;
						}
					}
					else {
						@sysEntry.statText = null;
					}
				}

				if (curNegStat > 0 || curPosStat > 0)
					text += "\n";

				if (curPosStat > 0)
					text += combine("\n", localize("#STT_TotalPos"), "#c:0f0#+", standardize(curPosStat), "#c#");

				if (curNegStat > 0)
					text += combine("\n", localize("#STT_TotalNeg"), "#c:f00#-", standardize(curNegStat), "#c#");

				statsTooltipText.setText(text);
				statsTooltip.setSize(dim2di(statsTooltip.getSize().width, statsTooltipText.getSize().height+8));
			}
		}
		else {
			curNegStat = -1.f;
			curPosStat = -1.f;
			prevHoveredStat = -1;

			statsTooltip.setVisible(false);
		}
	}
	/* }}} */
	/* {{{ Sub System hover information */
	void hoverSubSystem(int ID) {
		if (ID != hoveredSubSystemID) {
			hoveredSubSystemID = ID;

			if (ID == 0) {
				sysInfoPanel.setVisible(false);
				return;
			}

			float shipScale = s_to_f(scale.getText());
			const subSystemDef@ sys = getSubSystemDefByID(ID);	

			sysInfoPanel.setVisible(true);

			SubSystemFactory@ factory = @SubSystemComp(sys.ID, 1.f).createFactory(shipScale);
			factory.compare(SubSystemFactory(), false);

			sysTitle.setText(combine("#font:frank_12#",sys.getName(),"#font#\n",
						combine(localize("#level"), " ", i_to_s(factory.active.level))));
			
			string@ desc = sys.getDescription();
			uint statCount = factory.hintDeltaCount;			
			if(statCount > 0) {
				string@ statsText = "#r#\n\nStats:";
				for(uint i = 0; i < statCount; ++i) {
					string@ stat = localizeStatName(factory.getHintDeltaName(i), localeLayoutHint, true);
					if(stat is null)
						continue;				
					statsText += combine("\n#tab:25#", stat, ": ", standardizeAndColor(factory.getHintDelta(i)));
				}
				
				desc += statsText;
			}
			
			sysDesc.setText(desc);
			
			sysInfoPanel.fitChildren();
			sysInfoPanel.resetScrollPosition();
			
			sysImg.setImage(sys.getImage());

			sysCost.updateDefaults(factory.active);
		}
	}
	/* }}} */
	/* }}} */
	/* {{{ AI Settings tab */
	GuiListBox@ ai_list;
	GuiPanel@ ai_targ_panel;
	GuiPanel@ ai_behave_panel;
	GuiPanel@ ai_docking_panel;
	GuiPanel@ ai_carrier_panel;
	GuiPanel@ ai_orders_panel;

	GuiScrollBar@ ai_trg_hp_min;
	GuiScrollBar@ ai_trg_hp_max;

	GuiStaticText@ athmn_val;
	GuiStaticText@ athmx_val;
	GuiStaticText@ ai_customDefendCaption;
	GuiEditBox@ ai_trg_scale_min;
	GuiEditBox@ ai_trg_scale_max;
	GuiEditBox@ ai_customRange;
	GuiEditBox@ ai_customDefendRange;
	GuiCheckBox@ ai_orbit;
	GuiCheckBox@ ai_targetShips;
	GuiCheckBox@ ai_targetPlanets;
	GuiCheckBox@ ai_depositShips;
	GuiCheckBox@ ai_depositPlanets;
	GuiCheckBox@ ai_forceDamage;
	GuiCheckBox@ ai_forceScale;
	GuiCheckBox@ ai_depositStations;
	GuiCheckBox@ ai_multiTarget;
	GuiCheckBox@ ai_dockShips;
	GuiCheckBox@ ai_dockStations;
	GuiCheckBox@ ai_dockPlanets;
	GuiCheckBox@ ai_fullComplement;
	GuiCheckBox@ ai_replenish;
	GuiComboBox@ ai_allowFetch;
	GuiComboBox@ ai_engagementRange;
	GuiComboBox@ ai_allowDeposit;
	GuiComboBox@ ai_allowSupply;
	GuiComboBox@ ai_dockMode;
	GuiComboBox@ ai_defaultFighter;
	GuiComboBox@ ai_defaultStance;
	GuiComboBox@ ai_defendRange;
	GuiStaticText@ ai_fighterText;
	OrderCustomizer@ order_customizer;

	bool updateOrders;

	void initSettings(GuiPanel@ ele) {
		updateOrders = false;
		GuiElement@ parent = ele;

		@ai_list = GuiListBox(recti(pos2di(3, 0), dim2di(171, 434)), true, parent);
		ai_list.addItem(localize("#LE_AITARGET"));
		ai_list.addItem(localize("#LE_AIBEHAVIOR"));
		ai_list.addItem(localize("#LE_AIDOCKING"));
		ai_list.addItem(localize("#LE_AICARRIER"));
		ai_list.addItem(localize("#LE_AIORDERS"));
		ai_list.setSelected(0);

		parent.toGuiPanel().fitChildren();
		@ai_targ_panel = GuiPanel(recti(pos2di(185, 7), dim2di(743, 433)), false, SBM_Invisible, SBM_Invisible, ele);
		@parent = ai_targ_panel;

		GuiExtText@ targPrefs = GuiExtText(recti(pos2di(6,4), dim2di(450, 19)), parent);
		targPrefs.setText("#font:frank_12#"+localize("#LE_AITARGET")+"#font#");
		targPrefs.orphan(true);

		
		GuiStaticText(recti(pos2di(6,30), dim2di(152, 19)), localize("#LE_MinHp"), false, false, false, parent).orphan(true);
		@ai_trg_hp_min = GuiScrollBar(recti(pos2di(6,50), dim2di(132, 12)), true, parent );
		ai_trg_hp_min.setMax(100);
		ai_trg_hp_min.setLargeStep(10);
		ai_trg_hp_min.setSmallStep(1);
		
		@athmn_val = GuiStaticText(recti(pos2di(142,47), dim2di(70,19)), "0%", false, false, false, parent);
		athmn_val.orphan(true);
		
		GuiStaticText(recti(pos2di(212,30), dim2di(152, 19)), localize("#LE_MaxHp"), false, false, false, parent).orphan(true);
		@ai_trg_hp_max = GuiScrollBar(recti(pos2di(212,50), dim2di(132, 12)), true, parent );
		ai_trg_hp_max.setPos(100);
		ai_trg_hp_max.setMax(100);
		ai_trg_hp_max.setLargeStep(10);
		ai_trg_hp_max.setSmallStep(1);
		ai_trg_hp_max.setID(ai_trg_hp_min.getID());
		
		@athmx_val = GuiStaticText(recti(pos2di(350,47), dim2di(100,19)), "0%", false, false, false, parent);
		athmx_val.orphan(true);
		
		GuiStaticText(recti(pos2di(6,75), dim2di(152, 19)), localize("#LE_MinScale"), false, false, false, parent).orphan(true);
		@ai_trg_scale_min = GuiEditBox(recti(pos2di(6,95), dim2di(132, 19)), "0", true, parent );
		
		GuiStaticText(recti(pos2di(212,75), dim2di(152, 19)), localize("#LE_MaxScale"), false, false, false, parent).orphan(true);
		@ai_trg_scale_max = GuiEditBox(recti(pos2di(212,95), dim2di(132, 19)), "9999999", true, parent );

		@ai_forceDamage = GuiCheckBox(false, recti(pos2di(400,44), dim2di(232, 19)), localize("#LE_Forced"), parent);
		@ai_forceScale = GuiCheckBox(false, recti(pos2di(400,96), dim2di(232, 19)), localize("#LE_Forced"), parent);
		
		@ai_orbit = GuiCheckBox(false, recti(pos2di(516,44), dim2di(232, 19)), localize("#LE_Orbit"), parent);
		@ai_targetShips = GuiCheckBox(true, recti(pos2di(516,70), dim2di(232, 19)), localize("#LE_TargetShips"), parent);
		@ai_targetPlanets = GuiCheckBox(true, recti(pos2di(516,96), dim2di(232, 19)), localize("#LE_TargetPlanets"), parent);

		GuiStaticText(recti(pos2di(6, 126), dim2di(240, 19)), localize("#LE_EngagementRange"), false, false, false, parent).orphan(true);
		@ai_engagementRange = GuiComboBox(recti(pos2di(212, 126), dim2di(132, 19)), parent);
		ai_engagementRange.addItem(localize("#LER_Far"));
		ai_engagementRange.addItem(localize("#LER_Close"));
		ai_engagementRange.addItem(localize("#LER_PointBlank"));
		ai_engagementRange.addItem(localize("#LER_Custom"));

		@ai_customRange = GuiEditBox(recti(pos2di(350,126), dim2di(102, 19)), "0", true, parent );
		ai_customRange.setVisible(false);

		@ai_multiTarget = GuiCheckBox(true, recti(pos2di(516,126), dim2di(232, 19)), localize("#LE_MultiTarget"), parent);

		parent.toGuiPanel().fitChildren();
		@ai_behave_panel = GuiPanel(recti(pos2di(185, 7), dim2di(743, 433)), false, SBM_Invisible, SBM_Invisible, ele);
		ai_behave_panel.setVisible(false);
		@parent = ai_behave_panel;

		GuiExtText@ behaviorPerfs = GuiExtText(recti(pos2di(6,4), dim2di(450, 19)), parent);
		behaviorPerfs.setText("#font:frank_12#"+localize("#LE_AIBEHAVIOR")+"#font#");
		behaviorPerfs.orphan(true);

		GuiStaticText(recti(pos2di(6,30), dim2di(290, 19)), localize("#LE_allowFetch"), false, false, false, parent).orphan(true);

		@ai_allowFetch = GuiComboBox(recti(pos2di(294, 29), dim2di(132, 19)), parent);
		ai_allowFetch.addItem(localize("#LE_Auto"));
		ai_allowFetch.addItem(localize("#LE_Allow"));
		ai_allowFetch.addItem(localize("#LE_Deny"));

		GuiStaticText(recti(pos2di(6,56), dim2di(290, 19)), localize("#LE_allowDeposit"), false, false, false, parent).orphan(true);

		@ai_allowDeposit = GuiComboBox(recti(pos2di(294, 55), dim2di(132, 19)), parent);
		ai_allowDeposit.addItem(localize("#LE_Auto"));
		ai_allowDeposit.addItem(localize("#LE_Allow"));
		ai_allowDeposit.addItem(localize("#LE_Deny"));
		
		@ai_depositShips = GuiCheckBox(false, recti(pos2di(6,82), dim2di(232, 19)), localize("#LE_DepositShips"), parent);
		@ai_depositPlanets = GuiCheckBox(true, recti(pos2di(244,82), dim2di(232, 19)), localize("#LE_DepositPlanets"), parent);
		@ai_depositStations = GuiCheckBox(true, recti(pos2di(482,82), dim2di(232, 19)), localize("#LE_DepositStations"), parent);

		GuiStaticText(recti(pos2di(6,120), dim2di(290, 19)), localize("#LE_allowSupply"), false, false, false, parent).orphan(true);

		@ai_allowSupply = GuiComboBox(recti(pos2di(294, 119), dim2di(132, 19)), parent);
		ai_allowSupply.addItem(localize("#LE_Auto"));
		ai_allowSupply.addItem(localize("#LE_Allow"));
		ai_allowSupply.addItem(localize("#LE_Deny"));

		GuiStaticText(recti(pos2di(6,146), dim2di(290, 19)), localize("#LE_defaultStance"), false, false, false, parent).orphan(true);

		@ai_defaultStance = GuiComboBox(recti(pos2di(294, 145), dim2di(132, 19)), parent);
		ai_defaultStance.addItem(localize("#ST_Engage"));
		ai_defaultStance.addItem(localize("#ST_Defend"));
		ai_defaultStance.addItem(localize("#ST_HoldPosition"));
		ai_defaultStance.addItem(localize("#ST_HoldFire"));
		
		GuiStaticText(recti(pos2di(6,172), dim2di(290, 19)), localize("#LE_defaultDefendRange"), false, false, false, parent).orphan(true);

		@ai_defendRange = GuiComboBox(recti(pos2di(294, 171), dim2di(132, 19)), parent);
		ai_defendRange.addItem(localize("#ER_System"));
		ai_defendRange.addItem(localize("#ER_Local"));
		ai_defendRange.addItem(localize("#ER_Galaxy"));

		@ai_customDefendRange = GuiEditBox(recti(pos2di(400,171), dim2di(80, 19)), "40", true, parent );
		ai_customDefendRange.setVisible(false);

		@ai_customDefendCaption = GuiStaticText(recti(pos2di(485,172), dim2di(140, 19)), localize("#au"), false, false, false, parent);
		ai_customDefendCaption.setVisible(false);

		parent.toGuiPanel().fitChildren();
		@ai_docking_panel = GuiPanel(recti(pos2di(185, 7), dim2di(743, 433)), false, SBM_Invisible, SBM_Invisible, ele);
		ai_docking_panel.setVisible(false);
		@parent = ai_docking_panel;

		GuiExtText@ docking = GuiExtText(recti(pos2di(6,4), dim2di(450, 19)), parent);
		docking.setText("#font:frank_12#"+localize("#LE_AIDOCKING")+"#font#");
		docking.orphan(true);

		GuiStaticText(recti(pos2di(6,30), dim2di(240, 19)), localize("#LE_AutoDock"), false, false, false, parent).orphan(true);

		@ai_dockMode = GuiComboBox(recti(pos2di(244, 30), dim2di(282, 19)), parent);
		ai_dockMode.addItem(localize("#LE_Never"));
		ai_dockMode.addItem(localize("#LE_DockClear"));
		ai_dockMode.addItem(localize("#LE_DockContested"));
		
		@ai_dockShips = GuiCheckBox(true, recti(pos2di(6,55), dim2di(232, 19)), localize("#LE_DockShips"), parent);
		@ai_dockPlanets = GuiCheckBox(true, recti(pos2di(244,55), dim2di(232, 19)), localize("#LE_DockPlanets"), parent);
		@ai_dockStations = GuiCheckBox(true, recti(pos2di(482,55), dim2di(232, 19)), localize("#LE_DockStations"), parent);

		parent.toGuiPanel().fitChildren();
		@ai_carrier_panel = GuiPanel(recti(pos2di(185, 7), dim2di(743, 433)), false, SBM_Invisible, SBM_Invisible, ele);
		ai_carrier_panel.setVisible(false);
		@parent = ai_carrier_panel;

		GuiExtText@ carrier = GuiExtText(recti(pos2di(6,4), dim2di(450, 19)), parent);
		carrier.setText("#font:frank_12#"+localize("#LE_AICARRIER")+"#font#");
		carrier.orphan(true);

		@ai_fighterText = GuiStaticText(recti(pos2di(6,30), dim2di(240, 19)), localize("#LE_DefaultFighter"), false, false, false, parent);

		@ai_defaultFighter = GuiComboBox(recti(pos2di(244, 30), dim2di(282, 19)), parent);
		ai_defaultFighter.addItem(localize("#LE_None"));

		@ai_fullComplement = GuiCheckBox(true, recti(pos2di(6,56), dim2di(332, 19)), localize("#LE_FullComplement"), parent);
		@ai_replenish = GuiCheckBox(true, recti(pos2di(6,79), dim2di(332, 19)), localize("#LE_Replenish"), parent);

		parent.toGuiPanel().fitChildren();
		@ai_orders_panel = GuiPanel(recti(pos2di(185, 7), dim2di(743, 433)), false, SBM_Invisible, SBM_Invisible, ele);
		ai_orders_panel.setVisible(false);
		@parent = ai_orders_panel;

		GuiExtText@ orders = GuiExtText(recti(pos2di(6,4), dim2di(450, 19)), parent);
		orders.setText("#font:frank_12#"+localize("#LE_AIORDERS")+"#font#");
		orders.orphan(true);

		@order_customizer = OrderCustomizer(recti(pos2di(6, 30), dim2di(650, 420)), parent);

		parent.toGuiPanel().fitChildren();
	}
	
	void syncSettingsPosition(dim2di size) {
		// List of settings tabs
		ai_list.setPosition(pos2di(6, 6));
		ai_list.setSize(dim2di(171, size.height - 12));
	}

	void updateSettings(float time) {
	}

	void applySettingsToTempHull() {
		int allowFetch = ai_allowFetch.getSelected();
		int allowDeposit = ai_allowDeposit.getSelected();
		int allowSupply = ai_allowSupply.getSelected();
		float storageSize = 0.f;

		uint itemCount = subSystems.length();
		for(uint i = 0; i < itemCount; ++i) {
			subSysEntry@ entry = subSystems[i];
			const subSystemDef@ sys = getSubSystemDefByID(entry.sysID);

			if (allowFetch == 0 || allowDeposit == 0) {
				if (sys.hasTag("Storage")) {
					storageSize += entry.scale;
				}
			}
		}

		if (allowFetch == 0 && storageSize >= 4.f)
			allowFetch = 1;
		if (allowDeposit == 0 && storageSize >= 4.f)
			allowDeposit = 1;
		if (allowSupply == 0 && !order_customizer.hasOrder(OrdT_Supply))
			allowSupply = 1;

		{
			uint lowDmg = 100 - ai_trg_hp_max.getPos(), hiDmg = 100 - ai_trg_hp_min.getPos();
			if(lowDmg > 0 || hiDmg < 100)
				setTempHullTargetDamage(float(lowDmg) / 100.f, float(hiDmg) / 100.f, ai_forceDamage.isChecked());
			
			float lowScale = s_to_f(ai_trg_scale_min.getText()), hiScale = s_to_f(ai_trg_scale_max.getText());
			if(lowScale > 0.f || hiScale < 9999900.f)
				setTempHullTargetScale(lowScale, hiScale, ai_forceScale.isChecked());
			
			setTempHullOrbitTargets(ai_orbit.isChecked());
		}

		setTempHullAllowFetch(allowFetch == 1);
		setTempHullAllowDeposit(allowDeposit == 1);
		setTempHullAllowSupply(allowSupply == 1);
		setTempHullAllowTargets(ai_targetShips.isChecked(), ai_targetPlanets.isChecked());
		setTempHullDepositTargets(ai_depositShips.isChecked(), ai_depositPlanets.isChecked(), ai_depositStations.isChecked());
		setTempHullDockTargets(ai_dockShips.isChecked(), ai_dockPlanets.isChecked(), ai_dockStations.isChecked());

		setTempHullDockMode(ai_dockMode.getSelected() == 0 ? DM_Never : (ai_dockMode.getSelected() == 1 ? DM_Clear : DM_Contested));
		setTempHullMultiTarget(ai_multiTarget.isChecked());

		setTempHullCarrierMode(CarrierMode((ai_fullComplement.isChecked() ? uint(CM_FullComplement) : 0) |
								  (ai_replenish.isChecked() ? uint(CM_Replenish) : 0)));

		if (ai_engagementRange.getSelected() > 0)
			setTempHullEngagementRange(s_to_f(ai_customRange.getText()));
		else
			setTempHullEngagementRange(-1.f);

		setTempHullDefendRange(getDefendRange());
		setTempHullDefaultStance(getDefaultStance());

		order_customizer.applyToTempHull();
	}

	void applySettingsToActiveHull() {
		int allowFetch = ai_allowFetch.getSelected();
		int allowDeposit = ai_allowDeposit.getSelected();
		int allowSupply = ai_allowSupply.getSelected();
		float storageSize = 0.f;

		float maxRange = 0.f;
		float minRange = 0.f;

		uint itemCount = subSystems.length();
		for(uint i = 0; i < itemCount; ++i) {
			subSysEntry@ entry = subSystems[i];
			const subSystemDef@ sys = getSubSystemDefByID(entry.sysID);

			if (allowFetch == 0 || allowDeposit == 0) {
				if (sys.hasTag("Storage")) {
					storageSize += entry.scale;
				}
			}
		}

		if (allowFetch == 0 && storageSize >= 4.f)
			allowFetch = 1;
		if (allowDeposit == 0 && storageSize >= 4.f)
			allowDeposit = 1;
		if (allowSupply == 0 && !order_customizer.hasOrder(OrdT_Supply))
			allowSupply = 1;

		{
			uint lowDmg = 100 - ai_trg_hp_max.getPos(), hiDmg = 100 - ai_trg_hp_min.getPos();
			if(lowDmg > 0 || hiDmg < 100)
				setActiveHullTargetDamage(float(lowDmg) / 100.f, float(hiDmg) / 100.f, ai_forceDamage.isChecked());
			
			float lowScale = s_to_f(ai_trg_scale_min.getText()), hiScale = s_to_f(ai_trg_scale_max.getText());
			if(lowScale > 0.f || hiScale < 9999900.f)
				setActiveHullTargetScale(lowScale, hiScale, ai_forceScale.isChecked());
			
			setActiveHullOrbitTargets(ai_orbit.isChecked());
		}

		setActiveHullAllowFetch(allowFetch == 1);
		setActiveHullAllowDeposit(allowDeposit == 1);
		setActiveHullAllowSupply(allowSupply == 1);
		setActiveHullAllowTargets(ai_targetShips.isChecked(), ai_targetPlanets.isChecked());
		setActiveHullDepositTargets(ai_depositShips.isChecked(), ai_depositPlanets.isChecked(), ai_depositStations.isChecked());
		setActiveHullDockTargets(ai_dockShips.isChecked(), ai_dockPlanets.isChecked(), ai_dockStations.isChecked());

		setActiveHullDockMode(ai_dockMode.getSelected() == 0 ? DM_Never : (ai_dockMode.getSelected() == 1 ? DM_Clear : DM_Contested));
		setActiveHullMultiTarget(ai_multiTarget.isChecked());

		setActiveHullCarrierMode(CarrierMode((ai_fullComplement.isChecked() ? uint(CM_FullComplement) : 0) |
								  (ai_replenish.isChecked() ? uint(CM_Replenish) : 0)));

		if (ai_engagementRange.getSelected() > 0)
			setActiveHullEngagementRange(s_to_f(ai_customRange.getText()));
		else
			setActiveHullEngagementRange(-1.f);

		setActiveHullDefendRange(getDefendRange());
		setActiveHullDefaultStance(getDefaultStance());

		order_customizer.applyToActiveHull();
	}

	void applySettingsToHull(const HullLayout@ layout) {
		// Default fighter
		uint defFighter = ai_defaultFighter.getSelected();
		if (defFighter > 0 && defFighter < uint(ai_defaultFighter.getItemCount())) {
			const HullLayout@ fighterHull = getActiveEmpire().getShipLayout(ai_defaultFighter.getItem(defFighter));

			if (layout !is null && fighterHull !is null)
				layout.set_defaultFighter(fighterHull);
		}

		// Update threshold
		layout.updateThreshold = s_to_f(updateThreshold.getText());
	}

	void settingsClear() {
		setEngagementRange(-1.f);
		setDefendRange(-1.f);
		setDefaultStance(AIS_Engage);
		ai_customDefendRange.setText("40");
		ai_customRange.setText("0");
		
		ai_trg_hp_min.setPos(0);
		ai_trg_hp_max.setPos(100);
		ai_forceDamage.setChecked(false);
		athmn_val.setText("0%");
		athmx_val.setText("100%");
		
		ai_trg_scale_min.setText("0");
		ai_trg_scale_max.setText("9999999");
		ai_forceScale.setChecked(false);
		
		ai_orbit.setChecked(false);
		ai_allowFetch.setSelected(0);
		ai_allowDeposit.setSelected(0);
		ai_allowSupply.setSelected(0);

		ai_targetShips.setChecked(true);
		ai_targetPlanets.setChecked(true);
		ai_depositShips.setChecked(false);
		ai_depositPlanets.setChecked(true);
		ai_depositStations.setChecked(true);
		ai_multiTarget.setChecked(true);

		ai_dockMode.setSelected(0);
		ai_dockShips.setChecked(true);
		ai_dockPlanets.setChecked(true);
		ai_dockStations.setChecked(true);

		refreshDefaultFighter(null);
		ai_fullComplement.setChecked(true);
		ai_replenish.setChecked(true);

		order_customizer.changeLayout(null);
	}

	void settingsSelectLayout(const HullLayout@ layout) {
		if (layout is null) {
			settingsClear();
			return;
		}

		ai_orbit.setChecked(layout.orbits);
		ai_allowFetch.setSelected(layout.allowFetch ? 1 : 2);
		ai_allowDeposit.setSelected(layout.allowDeposit ? 1 : 2);
		ai_allowSupply.setSelected(layout.allowSupply ? 1 : 2);
		ai_multiTarget.setChecked(layout.multiTarget);

		bool ships, planets, stations;

		layout.getAllowTargets(ships, planets);
		ai_targetShips.setChecked(ships);
		ai_targetPlanets.setChecked(planets);

		layout.getDepositTargets(ships, planets, stations);
		ai_depositShips.setChecked(ships);
		ai_depositPlanets.setChecked(planets);
		ai_depositStations.setChecked(stations);

		layout.getDockTargets(ships, planets, stations);
		ai_dockShips.setChecked(ships);
		ai_dockPlanets.setChecked(planets);
		ai_dockStations.setChecked(stations);

		refreshDefaultFighter(layout);
		setCarrierMode(layout.carrierMode);

		setDockMode(layout.dockMode);

		if (layout.engagementRange < 0) {
			ai_engagementRange.setSelected(0);
		}
		else {
			ai_engagementRange.setSelected(3);
			ai_customRange.setVisible(true);
			ai_customRange.setText(ftos_nice(layout.engagementRange));
		}

		setDefendRange(layout.defendRange);
		setDefaultStance(layout.defaultStance);
		
		float dmgLow, dmgHi;
		bool forced;

		if(layout.getTargetDamage(dmgLow, dmgHi, forced)) {
			ai_trg_hp_min.setPos(100 - int(dmgHi * 100.f));
			ai_trg_hp_max.setPos(100 - int(dmgLow * 100.f));
			ai_forceDamage.setChecked(forced);
		}
		else {
			ai_trg_hp_min.setPos(0);
			ai_trg_hp_max.setPos(100);
		}
		athmn_val.setText(ai_trg_hp_min.getPos() + "%");
		athmx_val.setText(ai_trg_hp_max.getPos() + "%");
		
		float scaleLow, scaleHi;
		if(layout.getTargetScales(scaleLow, scaleHi, forced)) {
			ai_trg_scale_min.setText(ftos_nice(scaleLow, 3));
			ai_trg_scale_max.setText(ftos_nice(scaleHi, 3));
			ai_forceScale.setChecked(forced);
		}
		else {
			ai_trg_scale_min.setText("0");
			ai_trg_scale_max.setText("9999999");
		}

		order_customizer.changeLayout(layout);
	}

	void settingsUpdateLayout(const HullLayout@ layout, HullStats@ stats) {
		if (layout is null)
			return;

		// Update order customizer
		if ((ai_orders_panel.isVisible() && settingsPanel.isVisible()) || order_customizer.newHull || updateOrders) {
			order_customizer.update(layout);
			updateOrders = false;
		}

		// Update custom engagement range
		float range = calculateEngagementRange(layout);
		ai_customRange.setText(ftos_nice(range));

		// Update which pages are visible
		bool hasCarrier = layout !is null && layout.hasSystemWithTag("ShipBay");
		bool hadCarrier = ai_list.getItemCount() > 4;

		if (hasCarrier != hadCarrier) {
			uint sel = ai_list.getSelected();
			ai_list.clear();
			ai_list.addItem(localize("#LE_AITARGET"));
			ai_list.addItem(localize("#LE_AIBEHAVIOR"));
			ai_list.addItem(localize("#LE_AIDOCKING"));
			if (hasCarrier) {
				ai_list.addItem(localize("#LE_AICARRIER"));
				if (sel == 3)
					sel = 4;
			}
			else if (sel == 4) {
				sel = 3;
			}
			ai_list.addItem(localize("#LE_AIORDERS"));
			ai_list.setSelected(sel >= 0 && sel < ai_list.getItemCount() ? sel : 0);

			sel = ai_list.getSelected();
			ai_targ_panel.setVisible(sel == 0);
			ai_behave_panel.setVisible(sel == 1);
			ai_docking_panel.setVisible(sel == 2);
			ai_carrier_panel.setVisible(hasCarrier && sel == 3);
			ai_orders_panel.setVisible((!hasCarrier && sel == 3) || sel == 4);
		}
	}

	void addOrderToDesign(OrderDescriptor@ ord) {
		OrderDesc@ desc = generateOrderDesc(ord, null);
		if (desc !is null) {
			order_customizer.addOrderToDefaults(desc);
			order_customizer.addOrderLast(desc);
		}

		order_customizer.newHull = true;
		order_customizer.hasChanges = false;
	}

	void drawSettings(GuiElement@ ele, recti pos) {
		pos2di topLeft = pos.UpperLeftCorner;
		pos2di botRight = pos.LowerRightCorner;
		dim2di size = pos.getSize();

		drawDarkArea(recti(topLeft + pos2di(7, 7), dim2di(170, size.height - 14)));
		drawVSep(recti(topLeft + pos2di(176, 6), dim2di(7, size.height - 12)));
		drawLightArea(recti(topLeft + pos2di(183, 7), botRight - pos2di(7, 7)));
	}

	EventReturn onSettingsEvent(GuiElement@ ele, const GUIEvent& evt) {
		switch (evt.EventType) {
			case GEVT_Listbox_Changed:
				if (evt.Caller is ai_list) {
					bool hasCarrier = ai_list.getItemCount() == 5;
					int sel = ai_list.getSelected();
					ai_targ_panel.setVisible(sel == 0);
					ai_behave_panel.setVisible(sel == 1);
					ai_docking_panel.setVisible(sel == 2);
					ai_carrier_panel.setVisible(hasCarrier && sel == 3);

					if ((!hasCarrier && sel == 3) || sel == 4) {
						ai_orders_panel.setVisible(true);
						updateLayout();
					}
					else
						ai_orders_panel.setVisible(false);
				}
			break;
			case GEVT_Checkbox_Toggled:
				if (evt.Caller is ai_fullComplement) {
					updateLayout();
				}
			break;
			case GEVT_ComboBox_Changed:
				if (evt.Caller is ai_engagementRange) {
					updateLayout();

					uint mode = ai_engagementRange.getSelected();
					ai_customRange.setVisible(mode == 3);
				}
				else if (evt.Caller is ai_defendRange) {
					uint mode = ai_defendRange.getSelected();
					ai_customDefendRange.setVisible(mode == 1);
					ai_customDefendCaption.setVisible(mode == 1);
				}
			break;
			case GEVT_Scrolled:
				if (evt.Caller is ai_trg_hp_min) {
					athmn_val.setText(ai_trg_hp_min.getPos() + "%");
				}
				else if (evt.Caller is ai_trg_hp_max) {
					athmx_val.setText(ai_trg_hp_max.getPos() + "%");
				}
			break;
		}
		return ER_Pass;
	}

	/* {{{ Settings accessors */
	void setTargetScales(float low, float hi, bool forced) {
		if(low > 0)
			ai_trg_scale_min.setText(ftos_nice(low, 3));
		if(hi < 9999999.f && hi > 0)
			ai_trg_scale_max.setText(ftos_nice(hi, 3));
		ai_forceScale.setChecked(forced);
	}

	void setTargetDamage(float low, float hi, bool forced) {
		ai_trg_hp_min.setPos(100 - int(hi * 100.f));
		athmn_val.setText(ai_trg_hp_min.getPos() + "%");
		ai_trg_hp_max.setPos(100 - int(low * 100.f));
		athmx_val.setText(ai_trg_hp_max.getPos() + "%");
		ai_forceDamage.setChecked(forced);
	}

	void setOrbits(bool flag) {
		ai_orbit.setChecked(flag);
	}

	void setMultiTarget(bool multiTarget) {
		ai_multiTarget.setChecked(multiTarget);
	}

	void setDefendRange(float range) {
		if (range < -0.5f) {
			ai_defendRange.setSelected(0);
			ai_customDefendCaption.setVisible(false);
			ai_customDefendRange.setVisible(false);
		}
		else {
			if (range > 0.5f) {
				ai_defendRange.setSelected(1);
				ai_customDefendCaption.setVisible(true);
				ai_customDefendRange.setVisible(true);
				ai_customDefendRange.setText(f_to_s(range/1000.f, 1));
			}
			else {
				ai_defendRange.setSelected(2);
				ai_customDefendCaption.setVisible(false);
				ai_customDefendRange.setVisible(false);
			}
		}
	}

	float getDefendRange() {
		int sel = ai_defendRange.getSelected();
		if (sel == 0)
			return -1.f;
		if (sel == 2)
			return 0.f;
		return s_to_f(ai_customDefendRange.getText())*1000.f;
	}

	void setEngagementRange(float range) {
		if (range < 0) {
			ai_engagementRange.setSelected(0);
			ai_customRange.setVisible(false);
		}
		else {
			ai_engagementRange.setSelected(3);
			ai_customRange.setText(ftos_nice(range));
			ai_customRange.setVisible(true);
		}
	}

	float calculateEngagementRange(const HullLayout@ hull) {
		uint mode = ai_engagementRange.getSelected();

		if (mode == 3)
			return s_to_f(ai_customRange.getText());
		if (mode == 2)
			return 0.f;

		float minRange = 99999999999999.f;
		float maxRange = 0.f;

		// Calculate proper min and max weapons range
		uint sysCnt = hull.getSubSysCnt();
		for (uint i = 0; i < sysCnt; ++i) {
			const subSystem@ sys = hull.getSubSys(i);

			if (!sys.type.hasTag("Weapon"))
				continue;

			float range = sys.getHint("Local/Range");
			if (range <= 0)
				continue;

			if (range < minRange)
				minRange = range;
			if (range > maxRange)
				maxRange = range;
		}

		// Set the correct value
		if (mode == 0)
			return floor(maxRange * 0.6f);
		else if (mode == 1)
			return floor(minRange * 0.6f);
		else
			return -1.f;
	}

	void setAllowFetch(bool allow) {
		ai_allowFetch.setSelected(allow ? 1 : 2);
	}

	void setAllowDeposit(bool allow) {
		ai_allowDeposit.setSelected(allow ? 1 : 2);
	}

	void setAllowSupply(bool allow) {
		ai_allowSupply.setSelected(allow ? 1 : 2);
	}

	void setAllowTargets(bool ships, bool planets) {
		ai_targetShips.setChecked(ships);
		ai_targetPlanets.setChecked(planets);
	}

	void setDepositTargets(bool ships, bool planets, bool stations) {
		ai_depositShips.setChecked(ships);
		ai_depositPlanets.setChecked(planets);
		ai_depositStations.setChecked(stations);
	}

	void setDockTargets(bool ships, bool planets, bool stations) {
		ai_dockShips.setChecked(ships);
		ai_dockPlanets.setChecked(planets);
		ai_dockStations.setChecked(stations);
	}

	void setDefaultStance(AIStance stance) {
		switch (stance) {
			case AIS_Engage:
				ai_defaultStance.setSelected(0);
			break;
			case AIS_Defend:
				ai_defaultStance.setSelected(1);
			break;
			case AIS_HoldPosition:
				ai_defaultStance.setSelected(2);
			break;
			case AIS_HoldFire:
				ai_defaultStance.setSelected(3);
			break;
		}
	}

	AIStance getDefaultStance() {
		int sel = ai_defaultStance.getSelected();
		switch (sel) {
			case 0: return AIS_Engage;
			case 1: return AIS_Defend;
			case 2: return AIS_HoldPosition;
			case 3: return AIS_HoldFire;
		}
		return AIS_Engage;
	}

	void setCarrierMode(CarrierMode cm) {
		ai_fullComplement.setChecked(cm & CM_FullComplement != 0);
		ai_replenish.setChecked(cm & CM_Replenish != 0);
	}

	void refreshDefaultFighter(const HullLayout@ layout) {
		ai_defaultFighter.clear();
		ai_defaultFighter.addItem(localize("#LE_None"));

		const HullLayout@ fighter = null;
		if (layout !is null)
			@fighter = layout.defaultFighter;
		Empire@ emp = getActiveEmpire();
		uint layoutCount = emp.getShipLayoutCnt();
		uint sel = 0;
		uint j = 0;

		for(uint i = 0; i < layoutCount; ++i) {
			const HullLayout@ lay = emp.getShipLayout(i);
			if(lay.obsolete)
				continue;
			if (fighter is lay)
				sel = j+1;
			ai_defaultFighter.addItem(lay.getName());
			++j;
		}

		if (sel == 0) {
			if (fighter !is null) {
				sel = j+1;
				ai_defaultFighter.addItem(fighter.getName());
			}
		}

		ai_defaultFighter.setSelected(sel);
	}

	void setDefaultFighter(const string@ name) {
		ai_defaultFighter.clear();
		ai_defaultFighter.addItem(localize("#LE_None"));
		ai_defaultFighter.addItem(name);
		ai_defaultFighter.setSelected(1);
	}

	void setDockMode(DockingMode mode) {
		switch (mode) {
			case DM_Never: ai_dockMode.setSelected(0); break;
			case DM_Contested: ai_dockMode.setSelected(2); break;
			case DM_Clear: ai_dockMode.setSelected(1); break;
		}
	}
	/* }}} */
	/* }}} */
	/* {{{ Detailed statistics tab */
	GuiExtText@ statsTitle;
	GuiExtText@ statsList;
	GuiExtText@ statsValues;
	GuiExtText@ statsText;
	GuiListBox@ statsPage;
	GuiScripted@ statsGraph;
	StatGraph@ stat_graph;

	GuiButton@ stat_btn1;
	GuiButton@ stat_btn2;
	GuiButton@ stat_btn3;
	GuiButton@ stat_btn4;
	GuiButton@ stat_btn5;

	void initStats(GuiPanel@ ele) {
		// Detailed stats panel
		@statsTitle = GuiExtText(recti(pos2di(191, 11), dim2di(459, 18)), ele);
		statsTitle.setText("#font:frank_12#"+localize("#LB_Stats")+"#font#");

		@statsText = GuiExtText(recti(pos2di(191, 29), dim2di(735, 412)), ele);
		@statsList = GuiExtText(recti(pos2di(191, 29), dim2di(450, 394)), ele);
		@statsValues = GuiExtText(recti(pos2di(390, 29), dim2di(100, 412)), ele);

		@statsPage = GuiListBox(recti(pos2di(6, 6), dim2di(170, 434)), true, ele);
		statsPage.addItem(localize("#LD_Overview"));
		statsPage.addItem(localize("#LD_Weapons"));
		statsPage.addItem(localize("#LD_PowerPage"));
		statsPage.addItem(localize("#LD_FuelUsePage"));
		statsPage.addItem(localize("#LD_AmmoUsePage"));
		statsPage.addItem(localize("#LD_ControlPage"));
		statsPage.setSelected(0);
		
		int stat_btn_id = reserveGuiID();
		
		@stat_btn1 = ToggleButton(true, recti(pos2di(930 - 130,11), dim2di(120, 18)), "", ele); stat_btn1.setID(stat_btn_id);
		@stat_btn2 = ToggleButton(false, recti(pos2di(930 - 255,11), dim2di(120, 18)), "", ele); stat_btn2.setID(stat_btn_id);
		@stat_btn3 = ToggleButton(false, recti(pos2di(930 - 380,11), dim2di(120, 18)), "", ele); stat_btn3.setID(stat_btn_id);
		@stat_btn4 = ToggleButton(false, recti(pos2di(930 - 505,11), dim2di(120, 18)), "", ele); stat_btn4.setID(stat_btn_id);
		@stat_btn5 = ToggleButton(false, recti(pos2di(930 - 630,11), dim2di(120, 18)), "", ele); stat_btn5.setID(stat_btn_id);
	
		@stat_graph = StatGraph();
		@statsGraph = GuiScripted(recti(pos2di(187, 33), dim2di(733, 400)), stat_graph, ele);
		statsGraph.setVisible(false);
		stat_graph.init(statsGraph);
	}
	
	void syncStatsPosition(dim2di size) {
		statsPage.setSize(dim2di(171, size.height - 12));

		statsGraph.setSize(size - dim2di(197, 43));
		stat_graph.setSize(statsGraph.getSize());
	}

	void updateStats(float time) {
	}

	void statsSelectLayout(const HullLayout@ layout) {
	}

	void statsUpdateLayout(const HullLayout@ layout, HullStats@ stats) {
		if (statsPanel.isVisible() && layout !is null)
			RefreshDetailedStats(layout, stats);
	}

	void drawStats(GuiElement@ ele, recti pos) {
		pos2di topLeft = pos.UpperLeftCorner;
		pos2di botRight = pos.LowerRightCorner;
		dim2di size = pos.getSize();

		drawDarkArea(recti(topLeft + pos2di(7, 7), dim2di(170, size.height - 14)));
		drawVSep(recti(topLeft + pos2di(176, 6), dim2di(7, size.height - 12)));
		drawLightArea(recti(topLeft + pos2di(183, 7), botRight - pos2di(7, 7)));

		if (statsPage.getSelected() == 0) {
			drawVSep(recti(pos2di(botRight.x - 271, topLeft.y + 6), dim2di(7, size.height - 12)));
			drawRect(recti(pos2di(botRight.x - 265, topLeft.y + 7), pos2di(botRight.x - 7, botRight.y - 7)), Color(0xff000000));
		}
		else {
			drawLightArea(recti(topLeft + pos2di(183, 7), botRight - pos2di(7, 7)));
		}
	}

	EventReturn onStatsEvent(GuiElement@ ele, const GUIEvent& evt) {
		switch (evt.EventType) {
			case GEVT_Listbox_Changed:
				updateLayout();
			break;
			case GEVT_Clicked:
				if (evt.Caller.getID() == stat_btn1.getID()) {
					stat_btn1.setPressed(false);
					stat_btn2.setPressed(false);
					stat_btn3.setPressed(false);
					stat_btn4.setPressed(false);
					stat_btn5.setPressed(false);
				
					int lastPageMode = pageMode;
					if(evt.Caller is stat_btn1)
						pageMode = 0;
					else if(evt.Caller is stat_btn2)
						pageMode = 1;
					else if(evt.Caller is stat_btn3)
						pageMode = 2;
					else if(evt.Caller is stat_btn4)
						pageMode = 3;
					else if(evt.Caller is stat_btn5)
						pageMode = 4;
					if(lastPageMode != pageMode)
						updateLayout();
					
					evt.Caller.toGuiButton().setPressed(true);
				}
			break;
		}
		return ER_Pass;
	}

	void RefreshDetailedStats(const HullLayout@ hull, HullStats@ hs) {
		// Build correct page
		int page = statsPage.getSelected();
		switch (page) {
			case 0:
				BuildDetailedStatsOverview(hull, hs);
			break;
			case 1:
				BuildWeaponStats(hull, hs);
			break;
			case 2:
				BuildUsageStats(hull, hs, "Power", "Charge");
			break;
			case 3:
				BuildUsageStats(hull, hs, "FuelUse", "Fuel");
			break;
			case 4:
				BuildUsageStats(hull, hs, "AmmoUse", "Ammo");
			break;
			case 5:
				BuildUsageStats(hull, hs, "Control", null);
			break;
		}

		layoutStatsEle.setVisible(page == 0);
	}

	void BuildDetailedStatsOverview(const HullLayout@ hull, HullStats@ hs) {
		string@ text = "";
		string@ statsVals = "";

		// Flight time
		float fuel = hs.getHint("Fuel");
		float fuelUse = hs.getHint("FuelUse");

		if (fuel > 0 && fuelUse < 0) {
			float flightTime = fuel/-fuelUse;
			text += "\n"+localize("#LE_FlightTime")+":";
			statsVals += "\n"+secondsToTime(flightTime);
			
			float thrust = hs.getHint("Thrust");
			if(thrust > 0) {
				float accel = thrust / hs.getHint("Mass");
				float dist = 0.25f * accel * flightTime * flightTime;
				
				text += "\n"+localize("#LE_MaxDist")+":";
				statsVals += "\n"+standardize(dist/1000.f)+"AU";
			}
		}

		// Ammo firing time
		float ammo = hs.getHint("Ammo");
		float ammoUse = hs.getHint("AmmoUse");

		if (ammo > 0 && ammoUse < 0) {
			text += "\n"+localize("#LD_FireTime");
			statsVals += "\n"+secondsToTime(ammo/-ammoUse);
		}

		// Cumulative damage with ammo
		if (ammo > 0 && ammoUse < 0) {
			float ammoDPS = 0.f;
			uint cnt = hull.getSubSysCnt();
			for (uint i = 0; i < cnt; ++i) {
				const subSystem@ sys = hull.getSubSys(i);
				if (sys.hasHint("AmmoUse"))
					ammoDPS += sys.getHint("DPS");
			}

			float cumDPS = ammoDPS * (ammo / -ammoUse);
			if (cumDPS > 0) {
				text += "\n"+localize("#LD_CumDPS");
				statsVals += "\n"+standardize(cumDPS);
			}
		}

		// Charge lifetime for ZPM-powered ships
		float charge = hs.getHint("Charge");
		float powUse = hs.getHint("Power");

		if (powUse < 0 && charge > 0) {
			text += "\n"+localize("#LD_ChargeTime");
			statsVals += "\n"+secondsToTime(charge/-powUse);
		}

		// Health stats
		float hp = hs.getHint("HP");
		float hullhp = hs.getHint("Local/HullHP");
		float armor = hs.getHint("Armor");
		float shields = hs.getHint("Shields");

		// Hull hitpoints
		text += "\n\n\n"+localize("#LD_HullHP");
		statsVals += "\n\n\n"+standardize(hullhp);

		// Sub System hitpoints
		text += "\n"+localize("#LD_SubsHP");
		statsVals += "\n"+standardize(hp - armor - hullhp);

		// Armor hitpoints
		if (armor > 0) {
			text += "\n"+localize("#LD_ArmorHP");
			statsVals += "\n"+standardize(armor);
		}

		// Shield hitpoints
		if (shields > 0) {
			text += "\n"+localize("#LD_ShieldHP");
			statsVals += "\n"+standardize(shields);
		}

		text += "\n\n"+localize("#LD_TotalHP");
		statsVals += "\n#c:green##hline##c#\n"+standardize(hp + shields);

		errorBox.setVisible(true);
		layoutStats.ele.setVisible(true);
		
		hideStatButtons();

		statsList.setText(text);
		statsValues.setText(statsVals);
		statsText.setText("");
		statsTitle.setText("#font:frank_12#"+localize("#LB_Stats")+"#font#");
		statsGraph.setVisible(false);
	}

	void AddWeaponAsRange(const subSystem@ sys, float& maximum) {
		float range = sys.getHint("Local/Range") / 1000.f;
		
		if(range <= 0)
			return;
		
		stat_graph.addStat(range, sys.type.getImage(), combine(sys.type.getName(), " (", f_to_s(sys.scale, 2), ")"));
		maximum = max(range * 1.2f, maximum);
	}

	void AddWeaponAsDPS(const subSystem@ sys, float& maximum) {
		float dps = sys.getHint("DPS");
		
		if(dps <= 0)
			return;
		
		stat_graph.addStat(dps, sys.type.getImage(), combine(sys.type.getName(), " (", f_to_s(sys.scale, 2), ")"));
		maximum = max(dps * 1.2f, maximum);
	}

	void AddWeaponAsShotDamage(const subSystem@ sys, float& maximum) {
		float shot = max(sys.getHint("Local/DMGperShot"), sys.getHint("Local/Alpha"));
		
		if(shot <= 0)
			return;
		
		stat_graph.addStat(shot, sys.type.getImage(), combine(sys.type.getName(), " (", f_to_s(sys.scale, 2), ")"));
		maximum = max(shot * 1.2f, maximum);
	}

	void AddWeaponAsShotDelay(const subSystem@ sys, float& maximum) {
		float delay = sys.getHint("Local/Delay");
		if(sys.type.hasTag("ClipWeapon"))
			delay = (delay - sys.getHint("Local/ClipDelay")) / sys.getHint("Local/Clip");
		
		if(delay <= 0)
			return;
		
		stat_graph.addStat(delay, sys.type.getImage(), combine(sys.type.getName(), " (", f_to_s(sys.scale, 2), ")"));
		maximum = max(delay * 1.2f, maximum);
	}

	void AddWeaponAsAmmoUse(const subSystem@ sys, float& maximum) {
		float ammo = sys.getHint("AmmoUse") * -1.f;
		
		if(ammo <= 0)
			return;
		
		stat_graph.addStat(ammo, sys.type.getImage(), combine(sys.type.getName(), " (", f_to_s(sys.scale, 2), ")"));
		maximum = max(ammo * 1.2f, maximum);
	}

	void BuildWeaponStats(const HullLayout@ hull, HullStats@ hs) {
		stat_graph.clear();
		
		WeaponStats mode = WeaponStats(pageMode);
		
		float maximum = 0.01f;
		
		switch(mode) {
			case WS_Range:
				stat_graph.setSuffix(localize("#LDS_AU"));
				maximum = 0.25f;
				break;
			case WS_DPS:
				stat_graph.setSuffix(localize("#LDS_DPS"));
				break;
			case WS_ShotDamage:
				stat_graph.setSuffix(localize("#LDS_Damage"));
				break;
			case WS_ShotDelay:
				stat_graph.setSuffix(localize("#LDS_Delay"));
				break;
			case WS_AmmoUse:
				stat_graph.setSuffix(localize("#LDS_AmmoUse"));
				break;
		}
		
		uint sysCnt = hull.getSubSysCnt();
		for (uint i = 0; i < sysCnt; ++i) {
			const subSystem@ sys = hull.getSubSys(i);
			const subSystemDef@ def = sys.type;

			if(!def.hasTag("Weapon"))
				continue;
			
			switch(mode) {
				case WS_Range:
					AddWeaponAsRange(sys, maximum); break;
				case WS_DPS:
					AddWeaponAsDPS(sys, maximum); break;
				case WS_ShotDamage:
					AddWeaponAsShotDamage(sys, maximum); break;
				case WS_ShotDelay:
					AddWeaponAsShotDelay(sys, maximum); break;
				case WS_AmmoUse:
					AddWeaponAsAmmoUse(sys, maximum); break;
			}
		}
		
		stat_graph.maximum = maximum;
		stat_graph.minimum = 0.f;

		errorBox.setVisible(false);
		layoutStats.ele.setVisible(false);
		
		prepStatButtons("#LDSB_Range","#LDSB_DPS","#LDSB_ShotDmg","#LDSB_ShotDelay","#LDSB_AmmoUse");

		statsGraph.setVisible(true);
		statsText.setText("");
		statsValues.setText("");
		statsList.setText("");
		statsTitle.setText("#font:frank_12#"+localize("#LD_Weapons")+"#font#");
	}

	void BuildUsageStats(const HullLayout@ hull, HullStats@ hs, string@ stat, string@ availStat) {
		stat_graph.clear();
		
		float maximum = 0.1f;
		
		if(stat != "Control")
			stat_graph.setSuffix("/s");
		else
			stat_graph.setSuffix("");
		
		uint sysCnt = hull.getSubSysCnt();
		for (uint i = 0; i < sysCnt; ++i) {
			const subSystem@ sys = hull.getSubSys(i);
			const subSystemDef@ def = sys.type;

			float value = 0.f;
			if (sys.hasConsume(stat))
				value = -sys.getConsume(stat);
			else if (sys.hasRequire(stat))
				value = -sys.getRequire(stat);
			else if (sys.hasHint(stat))
				value = sys.getHint(stat);

			if(value != 0.f) {
				stat_graph.addStat(value, def.getImage(), combine(def.getName(), " (", f_to_s(sys.scale, 2), ")"));
				maximum = max(maximum, abs(value) * 1.33f);
			}
		}
		
		stat_graph.maximum = maximum;
		stat_graph.minimum = -maximum;

		float avail = 0.f;
		if(availStat !is null)
			avail = hs.getHint(availStat);
		else
			avail = hs.getHint(stat);

		errorBox.setVisible(false);
		layoutStats.ele.setVisible(false);
		
		hideStatButtons();

		statsGraph.setVisible(true);
		statsText.setText("");
		statsValues.setText("");
		statsList.setText("");
		statsTitle.setText(combine("#font:frank_12#", localize("#LD_"+stat+"Page"), "#tab:200#",
				(availStat !is null ? localize("#LD_"+availStat+"Avail") : localize("#LD_Avail")),
				standardize(avail)) + "#font#");
	}

	//Sets buttons to the specified text (localized), or hides the buttons if null
	void prepStatButtons(const string@ text1, const string@ text2, const string@ text3, const string@ text4, const string@ text5) {
		stat_btn1.setVisible(text1 !is null);
		if(text1 !is null)
			stat_btn1.setText(localize(text1));
			
		stat_btn2.setVisible(text2 !is null);
		if(text2 !is null)
			stat_btn2.setText(localize(text2));
			
		stat_btn3.setVisible(text3 !is null);
		if(text3 !is null)
			stat_btn3.setText(localize(text3));
			
		stat_btn4.setVisible(text4 !is null);
		if(text4 !is null)
			stat_btn4.setText(localize(text4));
			
		stat_btn5.setVisible(text5 !is null);
		if(text5 !is null)
			stat_btn5.setText(localize(text5));
	}

	void hideStatButtons() {
		prepStatButtons(null,null,null,null,null);
	}
	/* }}} */
};
/* }}} */
/* {{{ Sub System List */
enum ListMode {
	LM_Text,
	LM_IconsText,
	LM_Icons,
};

const ListMode defaultListMode = LM_IconsText;

class subSysList : ScriptedGuiHandler {
	GuiScripted@ ele;
	GuiScrollBar@ scroll;
	LayoutWindow@ win;

	uint[] subSystems;
	set_int existingSystems;

	ListMode mode;
	string@[] tags;

	int hovered;
	int selected;
	bool dragging;
	bool needScroll;

	subSysList(LayoutWindow@ window, GuiElement@ parent) {
		@win = window;
		@ele = GuiScripted(recti(), this, parent);
		mode = defaultListMode;

		@scroll = GuiScrollBar(recti(), false, ele);
		scroll.setVisible(false);

		hovered = -1;
		selected = -1;
		dragging = false;
		needScroll = false;
	}

	void setPosition(pos2di pos) {
		ele.setPosition(pos);
	}

	void setSize(dim2di size) {
		ele.setSize(size);

		recti rect(size.width - 16, 0, size.width, size.height);
		scroll.setPosition(rect.UpperLeftCorner);
		scroll.setSize(rect.getSize());

		scroll.setPageSize(size.height);
		scroll.setSmallStep(15);
		scroll.setLargeStep(size.height / 3);
	}

	void clear() {
		subSystems.resize(0);
		existingSystems.clear();
	}

	void addTag(string@ tag) {
		uint n = tags.length();
		tags.resize(n+1);
		@tags[n] = tag;
	}

	bool add(const subSystemDef@ def) {
		// Check if we already have the system
		uint sysID = def.ID;
		if (existingSystems.exists(sysID))
			return true;

		// Check if the system has all the required tags
		uint tagCnt = tags.length();
		if (tagCnt > 0) {
			bool hasTag = false;
			for (uint i = 0; i < tagCnt; ++i) {
				if (def.hasTag(tags[i])) {
					hasTag = true;
					break;
				}
			}

			if (!hasTag)
				return false;
		}

		// Add the new system
		uint n = subSystems.length();
		subSystems.resize(n+1);
		subSystems[n] = sysID;
		existingSystems.insert(sysID);
		return true;
	}

	void drawItem(const subSystemDef@ def, pos2di topLeft, dim2di size) {
		const Texture@ tex = def.getImage();

		switch (mode) {
			case LM_IconsText: {
				drawText(def.getName(), recti(topLeft + pos2di(38, 0), dim2di(size.width - 42, size.height)), white, false, true);
				drawTexture(tex, recti(topLeft + pos2di(2, 2), dim2di(32, 32)), recti(pos2di(0, 0), tex.size), white, true);
			} break;
			case LM_Icons: {
				drawTexture(tex, recti(topLeft + pos2di(0, 0), dim2di(55, 55)), recti(pos2di(0, 0), tex.size), white, true);
			} break;
			case LM_Text: {
				drawText(def.getName(), recti(topLeft + pos2di(4, 0), dim2di(size.width - 8, size.height)), white, false, true);
			} break;
		}
	}

	dim2di getItemSize(dim2di size) {
		switch (mode) {
			case LM_IconsText:
				return dim2di(size.width, 36);
			case LM_Text:
				return dim2di(size.width, 20);
			case LM_Icons:
				return dim2di(55, 55);
		}

		return dim2di(1, 1);
	}

	int getItem(pos2di relPos, dim2di eleSize) {
		if (relPos.x < 0 || relPos.y < 0)
			return -1;

		dim2di itSize = getItemSize(eleSize);
		int perLine = floor(eleSize.width / itSize.width);

		int row = floor(relPos.y / itSize.height);
		int col = floor(relPos.x / itSize.width);

		return (row * perLine) + col;
	}

	void checkScroll() {
		dim2di eleSize = ele.getSize();
		dim2di itSize = getItemSize(eleSize);
		int perLine = floor(eleSize.width / itSize.width);
		int lines = floor(eleSize.height / itSize.height);
		int itemCnt = int(subSystems.length());

		scroll.setVisible(perLine * lines < itemCnt && ele.isVisible());
		needScroll = scroll.isVisible();

		if (needScroll) {
			recti rect(eleSize.width - 16, 0, eleSize.width, eleSize.height);
			scroll.setPosition(rect.UpperLeftCorner);
			scroll.setSize(rect.getSize());

			dim2di eleSize = ele.getSize();
			eleSize.width -= 16;
			dim2di itSize = getItemSize(eleSize);

			int perLine = floor(eleSize.width / itSize.width);
			int lines = floor(eleSize.height / itSize.height);
			int itemCnt = int(subSystems.length());

			scroll.setMax(itemCnt / perLine * itSize.height - eleSize.height);

			scroll.setPageSize(eleSize.height);
			scroll.setSmallStep(15);
			scroll.setLargeStep(eleSize.height / 3);
		}
	}

	void draw(GuiElement@ ele) {
		ele.toGuiScripted().setAbsoluteClip();
		const recti absPos = ele.getAbsolutePosition();
		pos2di topLeft = absPos.UpperLeftCorner;
		pos2di botRight = absPos.LowerRightCorner;
		dim2di size = absPos.getSize();

		if (needScroll) {
			if (mode == LM_Icons || scroll.isVisible()) {
				size.width -= 16;
				botRight.x -= 16;
			}
			topLeft.y -= scroll.getPos();
		}

		Color lineCol(0xff474747), white(0xffffffff), hoverCol(0x10ffffff), selectedCol(0xaa500000);

		dim2di itSize = getItemSize(size);
		int itWidth = itSize.width, itHeight = itSize.height;

		if (mode != LM_Icons && topLeft.y <= botRight.y && topLeft.y >= absPos.UpperLeftCorner.y)
			drawLine(topLeft, topLeft + pos2di(size.width+1, 0), lineCol);

		for (uint i = 0; i < subSystems.length(); ++i) {
			const subSystemDef@ def = getSubSystemDefByID(subSystems[i]);

			if (def is null)
				continue;

			if (selected == int(i))
				drawRect(recti(topLeft, itSize), selectedCol);
			if (hovered == int(i))
				drawRect(recti(topLeft, itSize), hoverCol);

			drawItem(def, topLeft, itSize);

			if (mode != LM_Icons && topLeft.y + itHeight <= botRight.y && topLeft.y >= absPos.UpperLeftCorner.y)
				drawLine(topLeft + pos2di(0, itHeight), topLeft + pos2di(size.width+1, itHeight), lineCol);

			topLeft.x += itWidth;
			if (topLeft.x + itWidth > botRight.x) {
				topLeft.x = absPos.UpperLeftCorner.x;
				topLeft.y += itHeight;
			}
		}

		clearDrawClip();
	}

	EventReturn onKeyEvent(GuiElement@ ele, const KeyEvent& evt) {
		return ER_Pass;
	}

	EventReturn onMouseEvent(GuiElement@ ele, const MouseEvent& evt) {
		switch (evt.EventType) {
			case MET_MOVED:
				if (ele.getAbsolutePosition().isPointInside(pos2di(evt.x, evt.y))) {
					if (dragging && uint(hovered) < subSystems.length()) {
						dragging = false;
						selected = hovered;
						win.dragNewSystem(getSubSystemDefByID(subSystems[hovered]));
						return ER_Absorb;
					}
					else {
						dim2di eleSize = ele.getSize();
						pos2di relPos = pos2di(evt.x, evt.y);
						relPos -= ele.getAbsolutePosition().UpperLeftCorner;

						if (needScroll) {
							eleSize.width -= 16;
							relPos.y += scroll.getPos();
						}

						hovered = getItem(relPos, eleSize);
						if (hovered > int(subSystems.length()))
							hovered = -1;

						if (uint(hovered) < subSystems.length())
							win.hoverSubSystem(subSystems[hovered]);
						else
							win.hoverSubSystem(0);

						return ER_Absorb;
					}
				}
				else {
					hovered = -1;
					return ER_Pass;
				}

			case MET_LEFT_DOWN:
				if (hovered >= 0 && hovered < int(subSystems.length())) {
					dragging = true;
				}
				return ER_Absorb;

			case MET_MIDDLE_UP:
				if (hovered >= 0 && hovered < int(subSystems.length())) {
					showSubSystemDetails(subSystems[hovered]);
					return ER_Absorb;
				}
			break;

			case MET_LEFT_UP:
				if (hovered >= 0 && hovered < int(subSystems.length())) {
					dragging = false;
					if (selected == hovered) {
						playSound("button_clk");
						win.addSubSystem(getSubSystemDefByID(subSystems[hovered]));
						win.updateLayout();
					}
					else {
						selected = hovered;
					}
					setGuiFocus(scroll);
				}
				return ER_Absorb;
		}
		return ER_Pass;
	}

	EventReturn onGUIEvent(GuiElement@ ele, const GUIEvent& evt) {		
		switch (evt.EventType) {
			case GEVT_Mouse_Over:
				if (getGuiFocus() is null || getGuiFocus().isAncestor(win.layoutPanel.getParent()))
					setGuiFocus(scroll);
			break;
			case GEVT_Mouse_Left:
				hovered = -1;
				win.hoverSubSystem(0);
			break;
		}
		return ER_Pass;
	}
};
/* }}} */
/* {{{ Sub System Icon */
pos2di layout_center(214,214);
float layout_scale = 64.f;

const Texture@ glowTex;
recti glowTexRect;

class subSysIcon : ScriptedGuiHandler {
	GuiScripted@ dragger;
	GuiButton@ x;
	GuiButton@ min;
	GuiButton@ plus;
	subSysEntry@ entry;
	LayoutWindow@ win;
	
	const Texture@ tex;
	recti texRect;

	string@ hoverText;
	
	bool dragging;
	bool canScale;
	pos2di origElePos;
	pos2di origCursorPos;
	
	float wheel_store;
	
	subSysIcon(subSysEntry@ subSys, LayoutWindow@ window, GuiElement@ parent) {
		@entry = @subSys;
		@win = window;
		
		uint sysID = subSys.sysID;
		float scale = subSys.scale;
		
		dragging = false;
		canScale = false;
		wheel_store = 0;
		
		@tex = subSys.getMaterial();
		texRect = tex.rect;
		
		int size = int(sqrt(scale) * layout_scale * sqrt(win.layoutSizeFactor));
		int glowExtra = (size * 8) / 100;
		
		const Empire@ emp = getActiveEmpire();
		const subSystemDef@ sysDef = getSubSystemDefByID(sysID);
		
		@dragger = GuiScripted(recti(0, 0, size, size), this, parent);
		@hoverText = combine("#font:stroked##a:center#", sysDef.getName(), "\n", f_to_s(scale, 2), "#font#");
		
		if(size > 64)
			size = (3 * size) / 4;
		else
			size -= 16;
		
		@x = GuiButton(recti(pos2di(size,0),dim2di(16,16)), null, dragger);
		x.setVisible(false);
		x.setImage("x_ico");
		
		if(!sysDef.hasTag("IgnoresScale")) {
			canScale = true;
			@min = GuiButton(recti(pos2di(0,size),dim2di(16,16)), null, dragger);
			min.setImage("minus_ico");
			min.setVisible(false);
			
			@plus = GuiButton(recti(pos2di(size,size),dim2di(16,16)), null, dragger);
			plus.setImage("plus_ico");
			plus.setVisible(false);
		}

		updatePosition();
	}
	
	void syncScale() {
		if (dragger is null)
			return;
		float scale = entry.scale;
		int prevSize = dragger.getSize().width;
		int size = int(sqrt(scale) * layout_scale * sqrt(win.layoutSizeFactor));
		
		if(size == prevSize)
			return;
		
		dragger.setSize(dim2di(size, size));

		const subSystemDef@ sysDef = getSubSystemDefByID(entry.sysID);
		@hoverText = combine("#font:stroked##a:center#", sysDef.getName(), "\n", f_to_s(entry.scale, 2), "#font#");
		
		//Make sure scaling expands in both directions, around the center of the icon
		dragger.setPosition(dragger.getPosition() + pos2di((prevSize - size) / 2, (prevSize - size) / 2));
		
		int iconDist = size;
		if(size > 64)
			iconDist = (3 * size) / 4;
		else
			iconDist -= 16;
		
		x.setPosition(pos2di(iconDist,0));
		if(@min != null) {
			min.setPosition(pos2di(0,iconDist));
			if(!entry.canScaleDown())
				min.setVisible(false);
			
			plus.setPosition(pos2di(iconDist,iconDist));
			if(!entry.canScaleUp())
				plus.setVisible(false);
		}
	}
	
	bool syncPosition() {
		syncScale();
		
		pos2df newPos = getPosition();
		
		if(!entry.setPosition(newPos)) {
			float dist = sqrt(sqr(newPos.x) + sqr(newPos.y));
			float newLen = 0.995f * (maxRadius - sqrt(entry.scale) / 2.f);

			entry.setPosition( pos2df( newPos.x * newLen / dist,
									   newPos.y * newLen / dist) );
			updatePosition();
			return false;
		}
		
		updatePosition();
		return true;
	}
	
	void updatePosition() {
		float size = dragger.getSize().width;
		pos2df pos = pos2df(layout_center.x, layout_center.y);
		pos += pos2df(entry.position.x * layout_scale,
					  entry.position.y * layout_scale);
		pos = pos2df(pos.x * win.layoutSizeFactor,
					 pos.y * win.layoutSizeFactor);
		pos -= pos2df(size / 2.f, size / 2.f);

		pos2di physPos(pos.x, pos.y);
		dragger.setPosition(physPos);
	}
	
	void ScaleDown() {
		if(shiftKey)
			entry.decrementScale();
		else
			entry.scaleDown();
		
		syncPosition();
	}
	
	void ScaleUp() {
		if(shiftKey)
			entry.incrementScale();
		else
			entry.scaleUp();
		
		syncPosition();
	}

	void remove() {
		if (shiftKey) {
			uint cnt = win.subSystemIcons.length();
			for (uint i = 0; i < cnt; ++i) {
				if (win.subSystemIcons[i].entry.sysID == entry.sysID) {
					win.subSystemIcons[i].entry.remove();
					win.subSystemIcons[i].update();
				}
			}
		}
		else {
			entry.remove();
			update();
		}

		win.updateLayout();
		win.hideSubSystemDelta();
	}
	
	pos2df getPosition() {
		if (dragger is null)
			return pos2df();

		pos2di pos = dragger.getPosition();
		dim2di size = dragger.getSize();

		pos2df layPos = pos2df(pos.x, pos.y);
		layPos += pos2df(size.width / 2.f, size.height / 2.f);
		layPos = pos2df(layPos.x / win.layoutSizeFactor,
					    layPos.y / win.layoutSizeFactor);
		layPos -= pos2df(layout_center.x, layout_center.y);
		layPos = pos2df(layPos.x / layout_scale,
					    layPos.y / layout_scale);

		makeDropPosition(layPos, entry.scale, 0.8f);

		return layPos;
	}
	
	void showButtons(bool show) {
		if(show) {
			if(@min != null) {
				min.setVisible(entry.canScaleDown());
				plus.setVisible(entry.canScaleUp());
			}
			x.setVisible(true);
		}
		else {
			if(@min != null) {
				min.setVisible(false);
				plus.setVisible(false);
			}
			x.setVisible(false);
		}
	}
	
	//Returns true if this entry should be removed
	bool update() {
		if(!entry.checkExists()) {
			if(dragger !is null) {
				if (getGuiFocus() is null || getGuiFocus().isAncestor(dragger))
					setGuiFocus(dragger.getParent());
				dragger.remove();
				@dragger = null;
			}
			return true;
		}
		return false;
	}
	
	void draw(GuiElement@ ele) {
		recti eleRect = ele.getAbsolutePosition();
		int glowExtra = (eleRect.getWidth() * 8) / 100;
		
		if(entry.linksTo !is null) {
			Color col = Color(255, 255, 255, 255);

			drawTexture(glowTex, recti(eleRect.UpperLeftCorner - pos2di(glowExtra,glowExtra),
						eleRect.getSize() + dim2di(glowExtra*2,glowExtra*2)), glowTexRect, col, true);
		}

		bool hasStat = false;
		Color sysCol(255, 255, 255, 255);
		if (entry.statMod < 0 && win.curNegStat > 0) {
			sysCol = Color(255, 255, 0, 0);
			hasStat = true;
		}
		else if (entry.statMod > 0 && win.curPosStat > 0) {
			sysCol = Color(255, 0, 255, 0);
			hasStat = true;
		}
		else if (win.ghostedIcon is this) {
			sysCol = Color(0xaaffffff);
		}

		drawTexture(tex, eleRect, texRect, sysCol, true);
		if (hasStat && entry.statText !is null)
			drawText(entry.statText, strStrokedFont, eleRect, Color(255,255,255,255), true, true);
	}
	
	EventReturn onKeyEvent(GuiElement@ ele,const KeyEvent& evt) {
		if (dragger is null)
			return ER_Pass;

		if (evt.pressed) {
			// Delete or Backspace removes the subsystem
			if (evt.key == 46 || evt.key == 8) {
				remove();
				return ER_Absorb;
			}
			// Arrow keys move
			else if (evt.key >= 37 && evt.key <= 40) {
				float amt = shiftKey ? 30.f : 15.f;
				switch (evt.key) {
					case 37: ele.setPosition(ele.getPosition() + pos2di(-amt, 0)); break;
					case 38: ele.setPosition(ele.getPosition() + pos2di(0, -amt)); break;
					case 39: ele.setPosition(ele.getPosition() + pos2di(amt, 0)); break;
					case 40: ele.setPosition(ele.getPosition() + pos2di(0, amt)); break;
				}
				syncPosition();
				win.updateLayout();
				return ER_Absorb;
			}
			// Return toggles size between smallest and largest
			else if (evt.key == 13) {
				if (canScale) {
					if (entry.scale <= maxScale / 2.f)
						entry.scale = maxScale;
					else
						entry.scale = minScale;

					syncPosition();
					win.updateLayout();
				}
				return ER_Absorb;
			}
			// Subtract scales down
			else if (canScale && (evt.key == 189 || evt.key == 109)) {
				ScaleDown();
				win.updateLayout();
				return ER_Absorb;
			}
			// Add scales up
			else if (canScale && (evt.key == 187 || evt.key == 107)) {
				ScaleUp();
				win.updateLayout();
				return ER_Absorb;
			}
		}
		return ER_Pass;
	}

	bool followMousePos(GuiElement@ ele) {
		if (dragger is null)
			return true;

		pos2di newPos = getMousePosition() - origCursorPos + origElePos;
		if(shiftKey) {
			float grid = 16.f * win.layoutSizeFactor;
			float alter = 8.f * win.layoutSizeFactor;

			newPos.x += ele.getSize().width / 2 - alter;
			newPos.y += ele.getSize().height / 2 - alter;

			newPos.x = int(round(float(newPos.x) / grid)) * grid;
			newPos.y = int(round(float(newPos.y) / grid)) * grid;

			newPos.x -= ele.getSize().width / 2 - alter;
			newPos.y -= ele.getSize().height / 2 - alter;
		}
		
		ele.setPosition(newPos);

		pos2df layPos = getPosition();
		entry.setPosition(layPos);
		syncPosition();

		return sqrt(sqr(layPos.x) + sqr(layPos.y)) < maxRadius + 0.8f;
	}
	
	EventReturn onMouseEvent(GuiElement@ ele,const MouseEvent& evt) {
		if (dragger is null)
			return ER_Pass;

		switch(evt.EventType) {
			case MET_MOVED:
				if(dragging) {
					if (ctrlKey) {
						dragging = false;
						win.dragNewSystem(getSubSystemDefByID(entry.sysID), entry.scale);
					}
					else {
						if (!followMousePos(ele)) {
							dragging = false;
							win.ghostDragSystem(this);
						}
					}
					return ER_Absorb;
				}
			break;
			case MET_LEFT_DOWN:
				{
					dragging = true;
					if(x.isVisible())
						win.setAllButtonShows(null);
					origElePos = ele.getPosition();
					origCursorPos = getMousePosition();
					ele.bringToFront();
				} return ER_Absorb;
			case MET_LEFT_UP:
				{
					dragging = false;
					syncPosition();
					win.updateLayout();
					win.setAllButtonShows(ele);
				} return ER_Absorb;
			case MET_RIGHT_UP:
				{
					playSound("button_clk");
					remove();
				} return ER_Absorb;
			case MET_WHEEL:
				{
					if (!canScale)
						return ER_Absorb;
					//When we turn the wheel the other way, don't use the previously stored amount
					if((wheel_store > 0) != (evt.wheel > 0))
						wheel_store = 0;
					
					wheel_store += evt.wheel;
					if (wheel_store > 0.5f) {
						if(!shiftKey)
							entry.decrementScale();
						else
							entry.scaleDown();
						wheel_store -= 0.5f;
					}
					else if(wheel_store < -0.5f) {
						if(!shiftKey)
							entry.incrementScale();
						else
							entry.scaleUp();
						wheel_store += 0.5f;
					}

					syncPosition();
					win.updateLayout();
					win.setAllButtonShows(ele);
				} return ER_Absorb;
			case MET_MIDDLE_UP:
				{
					showSubSystemDetails(entry.sysID);
				} return ER_Absorb;
		}
		return ER_Pass;
	}
	
	EventReturn onGUIEvent(GuiElement@ ele,const GUIEvent& event) {		
		if (dragger is null)
			return ER_Pass;

		if(event.EventType == GEVT_Clicked) {
			if(plus is event.Caller) {
				ScaleUp();
				win.updateLayout();
				win.hideSubSystemDelta();
				return ER_Absorb;
			}
			else if(x is event.Caller) {
				remove();
				return ER_Absorb;
			}
			else if(min is event.Caller) {
				ScaleDown();
				win.updateLayout();
				win.hideSubSystemDelta();
				return ER_Absorb;
			}
		}
		else if(event.EventType == GEVT_Mouse_Over) {
			if(dragging == false)
				win.setAllButtonShows(event.Caller);
			if (getGuiFocus() is null || getGuiFocus().isAncestor(win.layoutPanel.getParent()))
				if (!win.drag.dragging && !win.drag.resizing)
					setGuiFocus(ele);
			entry.hovered = true;
			return ER_Pass;
		}
		else if(event.EventType == GEVT_Mouse_Left) {
			win.setAllButtonShows(null);
			wheel_store = 0;
			entry.hovered = false;
		}
		else if(event.EventType == GEVT_Focus_Lost) {
			if(dragging)
				return ER_Absorb;
		}
		return ER_Pass;
	}
};
/* }}} */
/* {{{ Sub System Dragger */
class subSysDragger : ScriptedGuiHandler {
	GuiScripted@ dragger;
	LayoutWindow@ win;

	string@ name;
	string@ scaleText;

	const subSystemDef@ def;
	const Texture@ tex;
	recti texRect;
	float scale;
	int size;

	float wheel_store;
	bool canScale;
	pos2di offset;
	subSysEntry@ dragEntry;
	
	subSysDragger(subSysEntry@ entry, LayoutWindow@ window, GuiElement@ parent) {
		@dragEntry = entry;
		@def = getSubSystemDefByID(entry.sysID);
		@win = window;
		scale = entry.scale;
		wheel_store = 0;
		canScale = !def.hasTag("IgnoresScale");
		
		@tex = def.getImage();
		texRect = tex.rect;

		@name = def.getName();
		@scaleText = f_to_s(scale, 2);
		
		size = int(sqrt(scale) * layout_scale * sqrt(win.layoutSizeFactor));
		@dragger = GuiScripted(recti(0, 0, getScreenWidth(), getScreenHeight()), this, parent);
		dragger.bringToFront();
		setGuiFocus(dragger);
	}

	subSysDragger(const subSystemDef@ subSys, float Scale, LayoutWindow@ window, GuiElement@ parent) {
		@def = subSys;
		@win = window;
		scale = Scale;
		wheel_store = 0;
		canScale = !def.hasTag("IgnoresScale");
		
		@tex = subSys.getImage();
		texRect = tex.rect;

		@name = subSys.getName();
		@scaleText = f_to_s(scale, 2);
		
		size = int(sqrt(scale) * layout_scale * sqrt(win.layoutSizeFactor));
		@dragger = GuiScripted(recti(0, 0, getScreenWidth(), getScreenHeight()), this, parent);
		dragger.bringToFront();
		setGuiFocus(dragger);
	}
	
	void draw(GuiElement@ ele) {
		pos2di mousePos = getMousePosition();
		if (shiftKey) {
			pos2di circPos = win.shipCircle.getAbsolutePosition().UpperLeftCorner;

			pos2di newPos = mousePos;
			newPos.x -= circPos.x + 9;
			newPos.y -= circPos.y + 9;

			newPos.x = int(round(float(newPos.x) / 16.f)) * 16;
			newPos.y = int(round(float(newPos.y) / 16.f)) * 16;

			newPos.x += circPos.x + 9;
			newPos.y += circPos.y + 9;

			offset = newPos - mousePos;
		}
		else {
			offset = pos2di(0, 0);
		}

		recti eleRect(mousePos + offset - pos2di(size/2, size/2), dim2di(size, size));
		recti namePos = recti(eleRect.UpperLeftCorner - pos2di(100, 34), dim2di(200+size, 17));
		recti scalePos = recti(eleRect.UpperLeftCorner - pos2di(100, 17), dim2di(200+size, 17));

		drawText(name, strStrokedFont, namePos, Color(0xffffffff), true, true);
		drawText(scaleText, strStrokedFont, scalePos, Color(0xffffffff), true, true);

		if (dragEntry is null)
			drawTexture(tex, eleRect, texRect, Color(0xffffffff), true);
		else
			drawTexture(tex, eleRect, texRect, Color(0xaaffffff), true);
	}
	
	//Finds the nearest integer power of two scale
	float getNearestScaleTick(float forScale, bool findGreater) {
		float log2 = log(forScale) / log(2.f);
		
		return pow(2.f, findGreater ? ceil(log2) : floor(log2) );
	}
	
	//Scaling up functions
	bool canScaleUp() {
		return scale < maxScale;
	}
	
	//Snaps to the nearest integer power of two scale greater than the current scale
	void scaleUp() {
		scale = min( getNearestScaleTick(scale, false) * 2.f, maxScale);
	}
	
	//Steps up by the smallest scale step
	void incrementScale() {
		scale = min( scale + minScale, maxScale);
	}
	
	//Scaling Down functions
	bool canScaleDown() {
		return scale > minScale;
	}
	
	//Snaps to the nearest integer power of two scale lesser than the current scale
	void scaleDown() {
		scale = max( getNearestScaleTick(scale, true) / 2.f, minScale);
	}
	
	//Steps down by the smallest scale step
	void decrementScale() {
		scale = max( scale - minScale, minScale);
	}

	//Get blueprint position
	pos2df getBlueprintPosition() {
		pos2di sysPos = getMousePosition() + offset;
		sysPos -= win.shipCircle.getAbsolutePosition().UpperLeftCorner;
		sysPos -= pos2di(layout_center.x * win.layoutSizeFactor,
						 layout_center.y * win.layoutSizeFactor);

		return pos2df(float(sysPos.x) / layout_scale / win.layoutSizeFactor,
					  float(sysPos.y) / layout_scale / win.layoutSizeFactor);
	}
	
	EventReturn onKeyEvent(GuiElement@ ele,const KeyEvent& evt) {
		return ER_Pass;
	}

	EventReturn onMouseEvent(GuiElement@ ele,const MouseEvent& evt) {
		switch(evt.EventType) {
			case MET_MOVED:
				if (dragEntry !is null) {
					pos2df bpPos = getBlueprintPosition();

					if (isValidPosition(bpPos)) {
						win.dropGhostSystem(true);
						return ER_Absorb;
					}
				}
				return ER_Absorb;
			case MET_LEFT_UP:
			case MET_RIGHT_UP:
				if (dragEntry is null)
					win.dropNewSystem();
				else
					win.dropGhostSystem(false);
				return ER_Absorb;
			case MET_WHEEL: {
				if (!canScale)
					return ER_Absorb;
				//When we turn the wheel the other way, don't use the previously stored amount
				if((wheel_store > 0) != (evt.wheel > 0))
					wheel_store = 0;
				
				wheel_store += evt.wheel;
				if (wheel_store > 0.5f) {
					if(!shiftKey)
						decrementScale();
					else
						scaleDown();
					size = int(sqrt(scale) * layout_scale * sqrt(win.layoutSizeFactor));
					wheel_store -= 0.5f;
					@scaleText = f_to_s(scale, 2);

					if (dragEntry !is null)
						dragEntry.scale = scale;
					win.updateLayout();
				}
				else if(wheel_store < -0.5f) {
					if(!shiftKey)
						incrementScale();
					else
						scaleUp();
					size = int(sqrt(scale) * layout_scale * sqrt(win.layoutSizeFactor));
					wheel_store += 0.5f;
					@scaleText = f_to_s(scale, 2);

					if (dragEntry !is null)
						dragEntry.scale = scale;
					win.updateLayout();
				}
			} return ER_Absorb;
		}
		return ER_Pass;
	}
	
	EventReturn onGUIEvent(GuiElement@ ele,const GUIEvent& event) {		
		return ER_Pass;
	}
};
/* }}} */
/* {{{ Sub System Entry */
const float maxRadius = 3.3359375f;
float minScale = 0.25f, maxScale = 4.f;

class subSysEntry {
	uint sysID;
	float scale;
	pos2df position;

	bool exists;
	bool isLink;
	subSysEntry@ linksTo;

	// Some display settings anchored to this entry,
	// should not impact anything else
	bool hovered;
	float statMod;
	string@ statText;
	
	//Finds the nearest integer power of two scale
	float getNearestScaleTick(float forScale, bool findGreater) {
		float log2 = log(forScale) / log(2.f);
		
		return pow(2.f, findGreater ? ceil(log2) : floor(log2) );
	}
	
	//Scaling up functions
	bool canScaleUp() {
		return scale < maxScale;
	}
	
	//Snaps to the nearest integer power of two scale greater than the current scale
	void scaleUp() {
		scale = min( getNearestScaleTick(scale, false) * 2.f, maxScale);
	}
	
	//Steps up by the smallest scale step
	void incrementScale() {
		scale = min( scale + minScale, maxScale);
	}
	
	//Scaling Down functions
	bool canScaleDown() {
		return scale > minScale;
	}
	
	//Snaps to the nearest integer power of two scale lesser than the current scale
	void scaleDown() {
		scale = max( getNearestScaleTick(scale, true) / 2.f, minScale);
	}
	
	//Steps down by the smallest scale step
	void decrementScale() {
		scale = max( scale - minScale, minScale);
	}
	
	bool setPosition(const pos2df &in newPos) {
		//Make sure that the outer edge of the Sub System doesn't go beyond the bounds of the ship's circle
		if( sqrt( sqr(newPos.x) + sqr(newPos.y)) <= maxRadius - sqrt(scale) / 2.f ) {
			position = newPos;
			return true;
		}
		return false;
	}
	
	void remove() {
		exists = false;
		if (linksTo !is null && linksTo.linksTo is this)
			@linksTo.linksTo = null;
	}
	
	bool checkExists() {
		return exists;
	}

	//NOTE: This is slow, don't call often
	void updateCollision(subSysEntry@[]& subSystems) {
		// Only links get to link to something
		if (!isLink)
			return;

		if (linksTo !is null) {
			// If the link is still valid, keep it
			pos2df relPos = linksTo.position - position;
			if(sqrt((relPos.x * relPos.x) + (relPos.y * relPos.y)) < (sqrt(scale) + sqrt(linksTo.scale)) / 2.f)
				return;

			// Discard invalid links
			if (linksTo.linksTo is this)
				@linksTo.linksTo = null;
			@linksTo = null;
		}

		for(uint i = 0; i < subSystems.length(); ++i) {
			subSysEntry@ subSys = @subSystems[i];
			if (subSys is this || !subSys.checkExists() || subSys.isLink)
				continue;
			pos2df relPos = subSys.position - position;
			if(sqrt((relPos.x * relPos.x) + (relPos.y * relPos.y)) < (sqrt(scale) + sqrt(subSys.scale)) / 2.f) {
				// Don't link if it still has a valid link
				if (subSys.linksTo !is null) {
					pos2df relPos = subSys.linksTo.position - subSys.position;
					if(sqrt((relPos.x * relPos.x) + (relPos.y * relPos.y)) < (sqrt(subSys.scale) + sqrt(subSys.linksTo.scale)) / 2.f)
						continue;
				}

				@linksTo = subSys;
				@subSys.linksTo = this;
				return;
			}
		}
	}
	
	int getCollision(subSysEntry@[]& subSystems) {
		if (linksTo is null)
			return -1;
		for(uint i = 0; i < subSystems.length(); ++i) {
			subSysEntry@ subSys = @subSystems[i];
			if(subSys is linksTo) {
				if (!subSys.checkExists())
					return -1;
				return i;
			}
		}
		return -1;
	}
	
	subSysEntry(uint SubSysID, float Scale, const pos2df &in pos) {
		sysID = SubSysID;
		@linksTo = null;
		@statText = null;
		statMod = 0;
		scale = Scale;
		position = pos;
		hovered = false;
		exists = true;
		isLink = hasTag("Link");
	}
	
	bool hasTag(const string@ tag) {
		return getSubSystemDefByID(sysID).hasTag(tag);
	}
	
	const Texture@ getMaterial() {
		return getSubSystemDefByID(sysID).getImage();
	}

	void generate(SubSystemFactory@ fact) {
		fact.objectSizeFactor = 15.f;
		fact.activeScale = scale;

		if (linksTo !is null && linksTo.checkExists()) {
			fact.linkedScale = linksTo.scale;
			fact.generateSubSystems(getSubSystemDefByID(sysID), getSubSystemDefByID(linksTo.sysID));
		}
		else {
			fact.generateSubSystems(getSubSystemDefByID(sysID), null);
		}
	}
};
/* }}} */
/* {{{ Sub System Comp */
class SubSystemComp {
	uint subSysID;
	float scale;
	bool isRealSubSys;
	
	uint linkedSubSysID;
	float linkedScale;
	bool isLinked;
	
	SubSystemComp() {
		isRealSubSys = false;
	}
	
	SubSystemComp(uint SubSysDefID, float subSysScale) {
		isRealSubSys = true;
		subSysID = SubSysDefID;
		scale = subSysScale;
		
		isLinked = false;
	}
	
	SubSystemComp(uint SubSysDefID, float subSysScale, int linkedSubSystDefID, float linkedSubSysScale) {
		isRealSubSys = true;
		subSysID = SubSysDefID;
		scale = subSysScale;
		
		if (linkedSubSystDefID != -1) {
			isLinked = true;
			linkedSubSysID = uint(linkedSubSystDefID);
			linkedScale = linkedSubSysScale;
		}
		else
			isLinked = false;
	}
	
	SubSystemFactory@ createFactory(float shipScale) const {
		SubSystemFactory@ fact = SubSystemFactory();
		
		if(isRealSubSys) {
			fact.objectScale = shipScale;
			fact.objectSizeFactor = 15.f; //Ships have 15 sub-system's worth of space
			fact.activeScale = scale;
			
			if(isLinked) {
				fact.linkedScale = linkedScale;
				fact.generateSubSystems(getSubSystemDefByID(subSysID), getSubSystemDefByID(linkedSubSysID));
			}
			else {
				fact.generateSubSystems(getSubSystemDefByID(subSysID), null);
			}
		}
		
		return fact;
	}
};
/* }}} */
/* {{{ Dialog callbacks */
class ImportCallback : MultiImportCallback {
	LayoutWindow@ win;

	ImportCallback(LayoutWindow@ window) {
		@win = window;
	}

	void call(MultiImportDialog@ dialog) {
		if (win is null || win.removed)
			return;

		string@ errors = "";
		uint cnt = dialog.getItemCount();
		for (uint i = 0; i < cnt; ++i) {
			string@ text = dialog.getItem(i);
			if (text is null)
				continue;

			import_layout(win, text);

			if (shiftKey) {
				string@ layName = hullEscape(win.name.getText());
				const HullLayout@ lay = getActiveEmpire().getShipLayout(layName);

				if (lay !is null)
					continue;
			}

			if (win.hasHardError)
				errors += localize(text)+":\n"+win.error+"\n\n";
			else
				win.saveLayout();
		}

		win.clearLayout();

		if (errors != "") {
			addMessageDialog(localize("#LIE_Title"), localize("#LIE_Desc")+"\n\n"+errors, null);
			playSound("deny");
		}
		else
			playSound("confirm");
	}
};

class ScaleCallback : ListSelectionCallback {
	LayoutWindow@ win;

	ScaleCallback(LayoutWindow@ window) {
		@win = window;
	}

	void call(ListSelectionDialog@ dialog) {
		if (win is null || win.removed)
			return;

		int sel = dialog.getSelected();
		if (uint(sel) < scaleValues.length())
			win.setScale(scaleValues[sel]);
	}
};
/* }}} */

LayoutWindowHandle@[] wins;
dim2di defaultSize;

void createLayoutWindow() {
	uint n = wins.length();
	wins.resize(n+1);
	@wins[n] = LayoutWindowHandle(makeScreenCenteredRect(defaultSize));
	wins[n].selectFirst();
	wins[n].bringToFront();
}

void closeLayoutWindow(LayoutWindow@ win) {
	int index = findLayoutWindow(win);
	if (index < 0) return;

	if (wins.length() > 1) {
		wins[index].remove();
		wins.erase(index);
	}
	else {
		wins[index].setVisible(false);
	}
	setGuiFocus(null);
}

GuiElement@ getLayoutWindow() {
	if (wins.length() == 0)
		return null;
	return wins[0].ele;
}

void toggleLayoutWindow() {
	bool anyVisible = false;
	for (uint i = 0; i < wins.length(); ++i)
		if (wins[i].isVisible())
			anyVisible = true;
	toggleLayoutWindow(!anyVisible);
}

void toggleLayoutWindow(bool show) {
	if (shiftKey || wins.length() == 0) {
		createLayoutWindow();
	}
	else {
		// Toggle all windows to a particular state
		for (uint i = 0; i < wins.length(); ++i) {
			wins[i].setVisible(show);
			if (show)
				wins[i].bringToFront();
		}
	}
}

bool ToggleLayoutWin(const GUIEvent@ evt) {
	if (evt.EventType == GEVT_Clicked) {
		toggleLayoutWindow();
		return true;
	}
	return false;
}

bool ToggleLayoutWin_key(uint8 flags) {
	if (flags & KF_Pressed != 0) {
		toggleLayoutWindow();
		return true;
	}
	return false;
}

int findLayoutWindow(LayoutWindow@ win) {
	for (uint i = 0; i < wins.length(); ++i)
		if (wins[i].script is win)
			return i;
	return -1;
}

void setBpVisible(bool vis) {
	topbar_button.setVisible(vis);
}

GuiButton@ topbar_button;
void init() {
	// Initialize some constants
	@glowTex = getMaterialTexture("layout_linked_glow");
	glowTexRect = glowTex.rect;

	minScale = getGameSetting("SS_MIN_SCALE", 0.25f);
	maxScale = getGameSetting("SS_MAX_SCALE", 4.f);

	int xres = getScreenWidth(), yres = getScreenHeight();

	if (xres >= 1028)
		defaultSize = dim2di(948, 555);
	else
		defaultSize = dim2di(932, 555);

	initSkin();

	// Toggle key
	bindFuncToKey("F3", "script:ToggleLayoutWin_key");

	// Topbar button
	@topbar_button = GuiButton(recti(pos2di(xres / 2 - 50, 0), dim2di(100, 25)), null, null);
	topbar_button.setSprites("TB_Blueprints", 0, 2, 1);
	topbar_button.setAppearance(BA_UseAlpha, BA_Background);
	topbar_button.setAlignment(EA_Center, EA_Top, EA_Center, EA_Top);
	bindGuiCallback(topbar_button, "ToggleLayoutWin");
}

void tick(float time) {
	for (uint i = 0; i < wins.length(); ++i)
		if (wins[i].isVisible())
			wins[i].update(time);
}
