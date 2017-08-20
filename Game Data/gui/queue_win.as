#include "~/Game Data/gui/include/dialog.as"
#include "~/Game Data/gui/include/gui_skin.as"
#include "~/Game Data/gui/include/pl_queue.as"
#include "/include/resource_grid.as"
#include "~/Game Data/gui/include/blueprints_sort.as"

import recti makeScreenCenteredRect(const dim2di &in rectSize) from "gui_lib";
import void loadPlanetQueue(Object@ pl) from "planet_win";
import void savePlanetQueue(Object@ pl) from "planet_win";

// {{{ EXPORTS
void hideQmWin() {
	queueWin.setVisible(false);
	clearEscapeEvent(winName);
}

void esc_qm_close() {
	queueWin.setVisible(false);
}

void showQmWin(bool bringToFront) {
	queueWin.setVisible(true);
	bindEscapeEvent(winName, "esc_qm_close");
	if(bringToFront)
		queueWin.bringToFront();
}

bool closeQmWin(const GUIEvent@ event) {
	if(event.EventType == GEVT_Clicked) {
		hideQmWin();
	}
	return false;
}

bool showQmWin_key(uint8 flags) {
	if(flags & KF_Pressed != 0) {
		Object@ obj = getSelectedObject(getSubSelection());
		if (obj !is null)
			triggerQueueWin(obj);
		return true;
	}
	return false;
}
// }}}
// {{{ ELEMENTS
const string@ winName = "queue_win";
const string@ strMetl = "Metals", strElec = "Electronics", strAdvp = "AdvParts", strFuel = "Fuel", strAmmo = "Ammo";
const string@ strLabr = "Labr";

Object@ curObj;

GuiDraggable@ queueWin;
GuiExtText@ title, progress;
GuiButton@ clearQueue, loadQueue, saveQueue, repeatQueue, pauseQueue;
ResourceGrid@ activeCost;
pl_queue@ queue;

GuiListBox@ shipsList;

// }}}
// {{{ Main Interface
void init() {
	// Bind key
	bindFuncToKey("q", "script:showQmWin_key");

	// Initial variables
	initSkin();

	// Window
	@queueWin = GuiDraggable(getSkinnable("Dialog"), makeScreenCenteredRect(dim2di(641, 320)), true, null);
	queueWin.setVisible(false);

	GuiButton@ closeButton = GuiButton(getSkinnable("CloseButton"), recti(pos2di(queueWin.getSize().width-30,0), dim2di(30,12)), null, queueWin);
	closeButton.orphan(true);
	bindGuiCallback(closeButton, "closeQmWin");

	// Object Title
	@title = GuiExtText(recti(pos2di(10, 21), dim2di(185, 20)), queueWin);
	@progress = GuiExtText(recti(pos2di(195, 21), dim2di(40, 20)), queueWin);

	// Resource grid
	@activeCost = ResourceGrid(queueWin, pos2di(11, 44), 2);
	activeCost.setSpaced(true);
	activeCost.setCellSize(dim2di(116, 17));
//	activeCost.setOffset(dim2di(0, 4));

	activeCost.add(SR_Advp, 0, 0);
	activeCost.add(SR_Labr, 0, 0);
	activeCost.add(SR_Elec, 0, 0);
	activeCost.add(SR_Fuel, 0, 0);
	activeCost.add(SR_Metl, 0, 0);
	activeCost.add(SR_Ammo, 0, 0);

	activeCost.update(0, "---");
	activeCost.update(1, "---");
	activeCost.update(2, "---");
	activeCost.update(3, "---");
	activeCost.update(4, "---");
	activeCost.update(5, "---");

	// Ships list
	@shipsList = GuiListBox(recti(pos2di(9, 95), dim2di(230, 215)), false, queueWin);
	bindGuiCallback(shipsList, "buildShip");

	// Buttons
	@clearQueue = Button(recti(pos2di(242, 21), dim2di(72, 18)), localize("#QM_Clear"), queueWin);
	@loadQueue = Button(recti(pos2di(317, 21), dim2di(72, 18)), localize("#QM_Load"), queueWin);
	@saveQueue = Button(recti(pos2di(392, 21), dim2di(72, 18)), localize("#QM_Save"), queueWin);
	@repeatQueue = ToggleButton(false, recti(pos2di(467, 21), dim2di(72, 18)), localize("#PL_Repeat"), queueWin);
	@pauseQueue = ToggleButton(false, recti(pos2di(542, 21), dim2di(72, 18)), localize("#PL_Pause"), queueWin);

	bindGuiCallback(clearQueue, "ClearQueue");
	bindGuiCallback(repeatQueue, "RepeatQueue");
	bindGuiCallback(pauseQueue, "PauseQueue");
	bindGuiCallback(loadQueue, "LoadQueue");
	bindGuiCallback(saveQueue, "SaveQueue");
	
	// Queued item list
	@queue = pl_queue();
	GuiScripted@ queueEle = GuiScripted( recti(pos2di(240,41), dim2di(391,270)), queue, queueWin );
	queueEle.orphan(true);
	queue.init(queueEle);
}

bool buildShip(const GUIEvent@ event) {
	if(@curObj != null) {
		if(event.EventType == GEVT_Listbox_Selected_Again) {
			int itemSelected = shipsList.getSelected();
			if(itemSelected >= 0) {
				const HullLayout@ temp = layouts.getLayout(itemSelected);

				if (ctrlKey) {
					multiBuild(curObj, temp);
				}
				else {
					int buildCount = shiftKey ? 5 : 1;
					while(buildCount > 0) {
						curObj.makeShip(temp);
						buildCount -= 1;
					}
				}
			}
			return true;
		}
	}
	return false;
}

bool ClearQueue(const GUIEvent@ event) {
	if (curObj !is null && event.EventType == GEVT_Clicked) {
		curObj.clearBuildQueue();
		return true;
	}
	return false;
}

bool RepeatQueue(const GUIEvent@ event) {
	if (curObj !is null && event.EventType == GEVT_Clicked) {
		curObj.setRepeatQueue(!curObj.getRepeatQueue());
		return true;
	}
	return false;
}

bool PauseQueue(const GUIEvent@ event) {
	if (curObj !is null && event.EventType == GEVT_Clicked) {
		curObj.setPauseQueue(!curObj.getPauseQueue());
		return true;
	}
	return false;
}

bool LoadQueue(const GUIEvent@ event) {
	if (curObj !is null && event.EventType == GEVT_Clicked) {
		loadPlanetQueue(curObj);
		return true;
	}
	return false;
}

bool SaveQueue(const GUIEvent@ event) {
	if (curObj !is null && event.EventType == GEVT_Clicked) {
		savePlanetQueue(curObj);
		return true;
	}
	return false;
}

void triggerQueueWin(Object@ obj) {
	// Check for planet or buildbay
	if (obj.toPlanet() !is null || (obj.toHulledObj() !is null && obj.toHulledObj().getHull().hasSystemWithTag("BuildBay"))) {
		@curObj = obj;
		showQmWin(true);

		title.setText("#font:frank_11##c:0d0#"+obj.getName()+"#c##font#");

		queue.syncToQueue(curObj);
		updateShips();
	}
}

SortedBlueprintList layouts;

void updateShips() {
	if (layouts.update(getActiveEmpire(), false))
		layouts.fill(shipsList);
}

void tick(float time) {
	if (curObj is null || !queueWin.isVisible())
		return;

	queue.syncToQueue(curObj);
	updateShips();

	pauseQueue.setPressed(curObj.getPauseQueue());
	repeatQueue.setPressed(curObj.getRepeatQueue());

	if (curObj.getConstructionQueueSize() > 0) {
		float perc = curObj.getConstructionProgress(0);
		progress.setText("#c:db0##font:frank_11##a:right#"+int(perc * 100.f)+"%#a##font##c#");
		progress.setVisible(true);

		float req = 0.f, done = 0.f;

		curObj.getConstructionCost(0, strAdvp, done, req);
		activeCost.update(0, done, req);

		curObj.getConstructionCost(0, strElec, done, req);
		activeCost.update(2, done, req);

		curObj.getConstructionCost(0, strMetl, done, req);
		activeCost.update(4, done, req);
		
		curObj.getConstructionCost(0, strLabr, done, req);
		activeCost.update(1, done, req);
		
		curObj.getConstructionCost(0, strFuel, done, req);
		activeCost.update(3, done, req);
		
		curObj.getConstructionCost(0, strAmmo, done, req);
		activeCost.update(5, done, req);
	} else {
		progress.setVisible(false);
		for (uint i = 0; i < 4; ++i)
			activeCost.update(i, "---");
	}
}
// }}}
