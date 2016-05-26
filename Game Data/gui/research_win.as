#include "~/Game Data/gui/include/notification_icon.as"
#include "~/Game Data/gui/include/gui_skin.as"
#include "~/Game Data/gui/include/research_queue.as"
#include "~/Game Data/gui/include/ResearchQueue.as"
#include "~/Game Data/gui/include/ResearchSaver.as"

import recti makeScreenCenteredRect(const dim2di &in rectSize) from "gui_lib";
const string@ locale_eta, locale_res_rate, locale_zoom, locale_level;

import void setTicker(string@ top, string@ bottom, string@ bottomRight) from "gui";
import void setTickerPercent(float,Color) from "gui";
import void showEventIndicator(GuiElement@ ele) from "gui";
import void hideEventIndicator(GuiElement@ ele) from "gui";
import void removeAllTechNotices() from "notifications";

/* {{{ Window handler */
class ResearchWindowHandle {
	ResearchWindow@ script;
	GuiScripted@ ele;

	ResearchWindowHandle(recti Position) {
		@script = ResearchWindow();
		@ele = GuiScripted(Position, script, null);

		script.init(ele);
		script.lastSize = Position.getSize();
		script.syncPosition(Position.getSize());
	}

	void bringToFront() {
		ele.bringToFront();
		setGuiFocus(ele);
		bindEscapeEvent(ele);
	}

	void setVisible(bool vis) {
		ele.setVisible(vis);

		if (vis)
			bindEscapeEvent(ele);
		else
			clearEscapeEvent(ele);
	}

	bool isVisible() {
		return ele.isVisible();
	}

	void update(ResearchWeb& web, float time) {
		script.position = ele.getPosition();
		script.update(web, time);
	}

	void remove() {
		clearEscapeEvent(ele);
		ele.remove();
		script.remove();
		setGuiFocus(null);
	}
};

int MIN_WIDTH = 300;
int MIN_HEIGHT = 200;

class ResearchWindow : ScriptedGuiHandler {
	bool removed;
	DragResizeInfo resize;
	pos2di position;
	dim2di lastSize;

	WebGridItem@[] webItems;

	WebGridItem@ hoveredItem;
	WebGridLink@ activeLink;

	GuiSkinnable@ detailsBG;
	GuiSkinnable@ detailsBorder;
	GuiExtText@ detailsName;
	GuiExtText@ detailsText;
	GuiStaticText@ linkDetails;

	GuiStaticText@ at_Name;
	GuiStaticText@ at_ETA;
	GuiStaticText@ at_Level;
	GuiImage@ at_Glow;

	GuiButton@ close;
	GuiStaticText@ researchRate;
	GuiStaticText@ zoomFactor;

	GuiScripted@ queueScript;
	research_queue@ guiQueue;
	GuiCheckBox@ automation;

	pos2di itemCenter;

	GuiZoomRegion@ webView;
	GuiDraggable@ webPlane;

	Empire@ lastEmp;
	const WebItem@ curActiveTech;
	float tooltipUpdateTime;
	int curActiveTechLink;
	int lastETA;
	int prevLevel;
	float progress;

	ResearchWindow() {
		curActiveTechLink = -2;
		lastETA = -2;
		prevLevel = -2;
		tooltipUpdateTime = 0.f;
		@lastEmp = null;
		removed = false;
	}

	void remove() {
		@hoveredItem = null;
		@activeLink = null;
		for (uint i = 0; i < webItems.length(); ++i)
			webItems[i].remove();
		webItems.resize(0);
	}

	void init(GuiElement@ ele) {
		/* Create web view */
		@webView = GuiZoomRegion(recti(), 0.20f, 1.20f, ele);
		@webPlane = GuiDraggable(recti(), true, webView);

		@guiQueue = research_queue();
		@queueScript = GuiScripted(recti(), guiQueue, ele);
		guiQueue.init(queueScript);

		@linkDetails = GuiStaticText( recti(pos2di(0,0), dim2di(128,17)), null, false, true, true, ele);
		linkDetails.setVisible(false);

		@at_Glow = GuiImage(pos2di(0,0), "glow", webPlane);
		at_Glow.setScaleImage(true);
		at_Glow.setVisible(false);
		at_Glow.setAlignment(EA_Scale,EA_Scale,EA_Scale,EA_Scale);

		@at_Name = GuiStaticText(recti(), null, false, false, false, ele);
		@at_Level = GuiStaticText(recti(), null, false, false, false, ele);
		@at_ETA = GuiStaticText(recti(), null, false, false, false, ele);

		at_Name.setTextAlignment(EA_Center, EA_Center);
		at_Level.setTextAlignment(EA_Center, EA_Center);

		@researchRate = GuiStaticText(recti(), null, false, false, false, ele);
		researchRate.setTextAlignment(EA_Center, EA_Center);

		@automation = GuiCheckBox(false, recti(), localize("#RW_Automate"), ele);
		automation.setToolTip(localize("#RWTT_Automate"));

		@zoomFactor = GuiStaticText(recti(), null, false, false, false, ele);

		@close = CloseButton(recti(), ele);

		// Hover items
		@detailsBG = GuiSkinnable(DarkArea, recti(7, 54, 0,0), ele);
		detailsBG.setVisible(false);

		@detailsBorder = GuiSkinnable(VSep, recti(243, 0, 250, 200), detailsBG);
		@detailsName = GuiExtText(recti(pos2di(10,6), dim2di(231,25)), detailsBG);
		@detailsText = GuiExtText(recti(pos2di(10,28), dim2di(231,313)), detailsBG);

		// Add items to web
		int webItemCount = getWebItemDescCount();	

		int width = uint(ceil(sqrt(float(webItemCount))));
		int planeWidth = (width * itemSpacing) * (680 * 2);
		int planeHeight = (width * itemSpacing) * (680 * 2);

		webPlane.setPosition(pos2di(planeWidth / -2 - itemMargin + (ele.getSize().width - 231),
					planeHeight / -2 - itemMargin + (ele.getSize().height - 7)));

		webPlane.setSize(dim2di(planeWidth, planeHeight));

		itemCenter = pos2di(planeWidth / 2, planeHeight / 2);

		for(int i = 0; i < webItemCount; ++i) {
			const WebItemDesc@ desc = getWebItemDesc(i);
			pos2df pos = desc.position;
			regWebItem(WebGridItem(this, desc, int(pos.x), int(pos.y)));
		}

		webView.setZoom(0.5, pos2di(0,0));

		// Match items to research web
		{
			ResearchWeb web;
			web.prepare(getActiveEmpire());

			matchAllItems(web);
		}
	}

	void setActiveLink(WebGridLink@ link) {
		if (activeLink is link)
			return;

		if (activeLink !is null)
			activeLink.deactive();
		if (link !is null) {
			link.active();
		}
		@activeLink = link;
	}

	void matchAllItems(ResearchWeb& web) {
		for (uint i = 0; i < webItems.length(); ++i)
			webItems[i].match(web);
		@lastEmp = getActiveEmpire();
	}

	void matchGlowToImage(GuiImage@ img) {
		dim2di imgSize = img.getSize();
		pos2di imgPos = img.getPosition();
		int sizeInc = int(float(imgSize.width) * 0.3f);
		imgPos -= pos2di(sizeInc, sizeInc);
		imgSize += dim2di(sizeInc * 2, sizeInc * 2);
		
		at_Glow.setPosition(imgPos);
		at_Glow.setSize(imgSize);
	}

	void regWebItem(WebGridItem@ item) {
		uint len = webItems.length();
		webItems.resize(len+1);
		@webItems[len] = @item;
	}

	WebGridItem@ findItem(const WebItemDesc@ desc) {
		uint itemCount = webItems.length();
		for(uint i = 0; i < itemCount; ++i)
			if(webItems[i].descriptor is desc)
				return webItems[i];
		return null;
	}

	void syncPosition(dim2di size) {
		recti rect;

		// Close button
		close.setPosition(pos2di(size.width-30, 0));
		close.setSize(dim2di(30, 12));

		bool drawQueue = true;
		if (size.width < 720) {
			size.width += 224;
			drawQueue = false;
		}

		// Correct area for web
		rect = recti(pos2di(7, 54), pos2di(size.width - 231, size.height - 7));
		webView.setPosition(rect.UpperLeftCorner);
		webView.setSize(rect.getSize());

		// Center web
		pos2di webOffset = pos2di((size.width - lastSize.width) / 2,
								  (size.height - lastSize.height) / 2);
		webPlane.setPosition(webPlane.getPosition() + webOffset);

		// Details popup box
		detailsBG.setSize(dim2di(250, rect.getSize().height));
		detailsBorder.setSize(dim2di(7, rect.getSize().height));

		// Top bar information
		int region = min(size.width*0.20f, 201.f), offset = 7;
		rect = recti(pos2di(offset+5, 26), pos2di(offset + region - 5,  44));
		at_Name.setPosition(rect.UpperLeftCorner);
		at_Name.setSize(rect.getSize());

		offset += region+4; region = min(size.width*0.14f, 131.f);
		rect = recti(pos2di(offset+5, 26), pos2di(offset + region - 5,  44));
		at_Level.setPosition(rect.UpperLeftCorner);
		at_Level.setSize(rect.getSize());

		offset += region+4; region = min(size.width*0.12f, 101.f);
		rect = recti(pos2di(offset+5, 26), pos2di(offset + region - 5,  44));
		at_ETA.setPosition(rect.UpperLeftCorner);
		at_ETA.setSize(rect.getSize());

		if (drawQueue) {
			rect = recti(pos2di(size.width - 220, 26), pos2di(size.width - 11,  44));
			researchRate.setPosition(rect.UpperLeftCorner);
			researchRate.setSize(rect.getSize());
			researchRate.setVisible(true);

			rect = recti(pos2di(size.width - 225, 56), pos2di(size.width - 7,  size.height - 14 - 24));
			queueScript.setPosition(rect.UpperLeftCorner);
			queueScript.setSize(rect.getSize());
			queueScript.setVisible(true);

			guiQueue.setPosition(rect.UpperLeftCorner);
			guiQueue.setSize(rect.getSize());

			rect = recti(pos2di(size.width - 221, size.height - 7 - 22), pos2di(size.width - 11,  size.height - 7));
			automation.setPosition(rect.UpperLeftCorner);
			automation.setSize(rect.getSize());
			automation.setVisible(true);
		}
		else {
			researchRate.setVisible(false);
			queueScript.setVisible(false);
			automation.setVisible(false);
		}

		// Zoom info
		zoomFactor.setPosition(pos2di(12, size.height - 25));
		zoomFactor.setSize(dim2di(80, 17));

		lastSize = size;
	}

	void update(ResearchWeb& web, float time) {
		// Update information in window
		{
			// Re-match items
			matchAllItems(web);

			// Update automation state
			automation.setChecked(automateResearch);

			// Update info about the active technology
			int linkIndex;
			const WebItem@ activeTech = web.getActiveTech(linkIndex);
			if (activeTech is null) {
				at_Name.setVisible(false);
				at_ETA.setVisible(false);
				at_Level.setVisible(false);
				at_Glow.setVisible(false);
			}
			else {
				WebGridItem@ activeItem = findItem(activeTech.descriptor);

				double rate = web.getResearchRate();
				bool isLink;
				float level = 0, progress, cost, maxLevel = 0, levelPct = 0, eta_sec = 0;
				
				if(linkIndex < 0) {
					activeTech.getLevels(level, progress, cost, maxLevel);
					this.progress = cost > 0 ? progress / cost : 1.f;
					levelPct = min(progress / cost, 1.f);
					eta_sec = rate > 0 ? (cost - progress) / rate : -1;
					isLink = false;
				}
				else {
					activeTech.getLinkLevels(linkIndex, progress, cost);
					this.progress = cost > 0 ? progress / cost : 1.f;
					levelPct = cost > 0 ? min(progress / cost, 1.f) : 1.f;
					eta_sec = rate > 0 ? (cost - progress) / rate : -1;
					isLink = true;
				}
		
				if(curActiveTech is null) {
					at_Name.setVisible(true);
					at_ETA.setVisible(true);
					at_Level.setVisible(true);
					at_Glow.setVisible(true);
				}

				if(curActiveTechLink != linkIndex || @curActiveTech != @activeTech) {
					if(isLink) {
						at_Name.setText(activeTech.descriptor.name + " - " + activeTech.descriptor.getLinkName(linkIndex));
						if (uint(linkIndex) < activeItem.links.length()) {
							matchGlowToImage(activeItem.links[linkIndex].icon);
							setActiveLink(activeItem.links[linkIndex]);
						}
						prevLevel = 0;
						at_Level.setText(null);
					}
					else {
						at_Name.setText(activeTech.descriptor.name);
						at_Level.setText(locale_level+int(level+1));
						prevLevel = level;
						matchGlowToImage(activeItem.icon);

						setActiveLink(null);
					}
				}
				else if(!isLink && int(level) != prevLevel) {
					at_Level.setText(locale_level+int(level+1));
					prevLevel = level;

					setActiveLink(null);
				}
		
				//Update ETA (And the research rate, as it is typically linked to the eta)
				int eta = int(ceil(eta_sec));
				if(eta != lastETA) {
					lastETA = eta;
					string@ str = locale_eta + formatETA(eta);
					
					at_ETA.setText(str);
					researchRate.setText(locale_res_rate + standardize(float(rate)));
				}
			}

			@curActiveTech = @activeTech;
			curActiveTechLink = linkIndex;

			zoomFactor.setText(locale_zoom + f_to_s(webView.getZoom(), 2) + "x");
		}

		// Update all the web items
		for (uint i = 0; i < webItems.length(); ++i)
			webItems[i].update();

		// Update tooltip
		if(detailsBG.isVisible() && @hoveredItem != null) {
			if (tooltipUpdateTime > 1.f) {
				hoveredItem.updateToolTip();
				tooltipUpdateTime = 0.f;
			}
			else {
				tooltipUpdateTime += time;
			}
		}

		// Synchronize queue
		guiQueue.syncToQueue(queue);
	}

	void draw(GuiElement@ ele) {
		ele.toGuiScripted().setAbsoluteClip();
		recti absPos = ele.getAbsolutePosition();
		pos2di topLeft = absPos.UpperLeftCorner;
		pos2di botRight = absPos.LowerRightCorner;
		dim2di size = absPos.getSize();
		bool drawQueue = true;
		if (size.width < 720) {
			size.width += 224;
			botRight.x += 224;
			drawQueue = false;
		}
		pos2di center = topLeft + pos2di(size.width / 2, size.height / 2);

		drawWindowFrame(absPos);

		if (drawQueue)
			drawResizeHandle(recti(botRight - pos2di(19, 19), botRight));
		else
			drawResizeHandle(recti(botRight - pos2di(19 + 224, 19), botRight - pos2di(224, 0)));

		// Research region
		drawLightArea(recti(topLeft+pos2di(7,54), botRight-pos2di(231,7)));

		// Queue box
		if (drawQueue) {
			drawVSep(recti(pos2di(botRight.x-232, topLeft.y+19), pos2di(botRight.x-225, botRight.y-6)));
			drawHSep(recti(pos2di(botRight.x-226, topLeft.y+48), pos2di(botRight.x-6, topLeft.y+55)));
			drawDarkArea(recti(pos2di(botRight.x-225, topLeft.y+54), botRight-pos2di(7,37)));
			drawHSep(recti(pos2di(botRight.x-226, botRight.y-38), pos2di(botRight.x-6, botRight.y-31)));
			drawDarkArea(recti(pos2di(botRight.x-225, botRight.y-32), botRight-pos2di(7,7)));
		}
		drawHSep(recti(pos2di(topLeft.x+6, topLeft.y+48), pos2di(botRight.x-230, topLeft.y+55)));

		// Active research box
		int region = min(size.width*0.20f, 201.f), offset = 7;
		drawVSepSmall(recti(pos2di(topLeft.x+region+offset, topLeft.y+19), dim2di(6, 31)));
		drawDarkArea(recti(pos2di(topLeft.x+offset, topLeft.y+20), dim2di(region+1, 29)));

		// Level Box
		offset += region+4; region = min(size.width*0.14f, 131.f);
		drawVSepSmall(recti(pos2di(topLeft.x+region+offset, topLeft.y+19), dim2di(6, 31)));
		drawDarkArea(recti(pos2di(topLeft.x+offset, topLeft.y+20), dim2di(region+1, 29)));

		// ETA Box
		offset += region+4;
		drawDarkArea(recti(pos2di(topLeft.x+offset, topLeft.y+20), dim2di(size.width-offset-231, 29)));

		// Progress bar
		offset += min(size.width*0.12f, 101.f)+4;
		drawProgressBar(recti(pos2di(topLeft.x+offset, topLeft.y+20), dim2di(size.width-offset-231, 28)), progress);

		// Rate Box
		if (drawQueue)
			drawDarkArea(recti(pos2di(botRight.x-225, topLeft.y+20), dim2di(218, 29)));

		clearDrawClip();
	}

	EventReturn onKeyEvent(GuiElement@ ele, const KeyEvent& evt) {
		return ER_Pass;
	}

	EventReturn onMouseEvent(GuiElement@ ele, const MouseEvent& evt) {
		DragResizeEvent re = handleDragResize(ele, evt, resize, MIN_WIDTH, MIN_HEIGHT);
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
			closeResearchWindow(this);
			return ER_Absorb;
		}

		if (evt.Caller is close && evt.EventType == GEVT_Clicked) {
			closeResearchWindow(this);
			return ER_Pass;
		}

		if (evt.Caller is automation && evt.EventType == GEVT_Checkbox_Toggled) {
			automateResearch = automation.isChecked();
			return ER_Pass;
		}

		if(evt.Caller is detailsBG || evt.Caller is detailsName || evt.Caller is detailsText) {
			if(evt.EventType == GEVT_Mouse_Over) {
				pos2di pos = detailsBG.getPosition();

				if (pos.x < 20) {
					pos.x = (webView.getSize().width - detailsBG.getSize().width + 7);
					detailsBorder.setPosition(pos2di(0, 0));
				}
				else {
					pos.x = 7;
					detailsBorder.setPosition(pos2di(243, 0));
				}

				detailsBG.setPosition(pos);
			}
			return ER_Absorb;
		}

		uint itemCount = webItems.length();
		for(uint i = 0; i < itemCount; ++i) {
			switch(webItems[i].onEvent(evt)) {
				case EHS_Handled:
					return ER_Pass;
				case EHS_Absorb:
					return ER_Absorb;
			}
		}
		return ER_Pass;
	}
};
/* }}} */
/* {{{ Web handler */
const int itemSpacing = 225;
const int itemMargin = itemSpacing / 2;
const bool useMomentaryLinks = true;
const Texture@ link_lines;
const Texture@ item_overlay;
Color color_item_locked, color_item_normal;

enum EventHandleState {
	EHS_Unhandled,
	EHS_Handled,
	EHS_Absorb
};

class GridInfo : ScriptedGuiHandler {
	float progress;
	int level;

	GridInfo() {
		progress = 0;
		level = 0;
	}

	void draw(GuiElement@ ele) {
		ele.toGuiScripted().setAbsoluteClip();

		// Draw progress glow
		if (progress > 0) {
			const recti absPos = ele.getAbsolutePosition();
			const pos2di topLeft = absPos.UpperLeftCorner;

			const int height = absPos.getSize().height;
			const float pr = (1-progress);

			drawTexture(item_overlay,
					recti(pos2di(topLeft.x, topLeft.y + floor(height*pr)),
						absPos.LowerRightCorner), recti(0, floor(128*pr), 128,
						128), Color(0xffffffff), true);

		}

		clearDrawClip();
	}

	EventReturn onKeyEvent(GuiElement@,const KeyEvent&) {
		return ER_Pass;
	}
	
	EventReturn onMouseEvent(GuiElement@,const MouseEvent&) {
		return ER_Pass;
	}
	
	EventReturn onGUIEvent(GuiElement@ ele, const GUIEvent& event) {
		return ER_Pass;
	}
};

class WebGridItem : ScriptedGuiHandler {
	ResearchWindow@ win;

	const WebItemDesc@ descriptor;
	const WebItem@ item;
	pos2di center;

	GuiScripted@ infoScripted;
	GridInfo@ info;

	GuiScripted@ scripted;
	GuiImage@ icon;
	GuiStaticText@ name;

	GuiStaticText@ level;

	WebGridLink@[] links;

	pos2df[] drawnLinks;
	bool[] linkState;
	bool hovered;
	bool even;

	WebGridItem(ResearchWindow@ Win, const WebItemDesc@ Descriptor, int hIndex, int vIndex) {
		@win = Win;
		@descriptor = @Descriptor;

		center = pos2di(hIndex * itemSpacing, vIndex * itemSpacing)
				+ pos2di(itemMargin, itemMargin) + win.itemCenter;

		even = hIndex % 2 == 0;
		if (!even)
			center.y += itemMargin;

		@scripted = GuiScripted(recti(center - pos2di(177, 179), dim2di(354, 357)), this, win.webPlane);
		scripted.setAlignment(EA_Scale,EA_Scale,EA_Scale,EA_Scale);

		@info = GridInfo();

		@name = null;
		@icon = null;
		@item = null;
		hovered = false;
	}

	void remove() {
		scripted.remove();
		links.resize(0);
		@win = null;
	}

	void match(ResearchWeb& web) {
		if (@name == null && @icon == null) {
			float prevZoom = win.webView.getZoom();
			win.webView.setZoom(1.f, pos2di(0,0));

			//Hack: We want to create these last so they're always on top
			@name = GuiStaticText(recti(center - pos2di((itemSpacing) / 2,100), dim2di(itemSpacing, 60)), descriptor.get_name(), false, false, false, win.webPlane);
			name.setFont("stroked");
			name.setTextAlignment(EA_Center, EA_Top);
			name.setAlignment(EA_Scale,EA_Scale,EA_Scale,EA_Scale);
			name.setVisible(false);

			@icon = GuiImage(center - pos2di(48,48), "res_web_unknown", win.webPlane);
			icon.setSize(dim2di(96,96));
			icon.setScaleImage(true);
			icon.setAlignment(EA_Scale,EA_Scale,EA_Scale,EA_Scale);
			icon.setClickThrough(false);

			@infoScripted = GuiScripted(recti(0, 0, 96, 96), info, icon);
			infoScripted.setAlignment(EA_Scale,EA_Scale,EA_Scale,EA_Scale);

			@level = GuiStaticText(recti(0, 0, 89, 96), null, false, false, false, icon);
			level.setTextAlignment(EA_Right, EA_Bottom);
			level.setAlignment(EA_Scale,EA_Scale,EA_Scale,EA_Scale);
			level.setColor(Color(0xff99ff33));
			level.setFont("stroked_subtitle");

			win.webView.setZoom(prevZoom, pos2di(0,0));
		}

		const WebItem@ prevItem = @item;
		@item = web.getItem(descriptor);
		uint cnt = descriptor.linkCount;
		
		if(@prevItem != @item) {
			if(item is null)
				icon.setImage("res_web_unknown");
			else
				icon.setImage(descriptor.icon);
			generateLinks();

			if(@item != null) {
				drawnLinks.resize(cnt);
				linkState.resize(cnt);
				pos2df techPos = descriptor.position;
				for (uint i = 0; i < cnt; ++i) {
					const WebItem@ lnk = item.getPossibleLinkEnd(i);
					if(@lnk == null) continue;

					drawnLinks[i] = lnk.descriptor.position - techPos;
					linkState[i] = web.isTechVisible(lnk.descriptor);
				}
			}
		}

		if(@item != null) {
			for (uint i = 0; i < cnt; ++i) {
				const WebItem@ lnk = item.getPossibleLinkEnd(i);
				if(@lnk == null) continue;
				linkState[i] = web.isTechVisible(lnk.descriptor);
			}
		}
	}

	void draw(GuiElement@ ele) {
		setDrawClip(win.webView.getAbsolutePosition());
		recti absPos = ele.getAbsolutePosition();
		float zoom = win.webView.getZoom();
		const pos2di topLeft = absPos.UpperLeftCorner;

		if(@name != null) {
			// Update name position to zoom level
			string@ descName = descriptor.name;
			dim2di txtsz = getTextDimension(descName, "stroked");
			name.setPosition(icon.getPosition()+pos2di(icon.getSize().width/2-(txtsz.width+4)/2, -txtsz.height-12*zoom));
			name.setSize(dim2di(txtsz.width+4, txtsz.height));
		}

		if(@item != null) {
			pos2di drawPos = pos2di(topLeft.x-78*zoom, topLeft.y-78*zoom);

			// Draw link lines
			uint cnt = descriptor.linkCount;
			for(uint i = 0; i < cnt; ++i) {
				pos2df relPos = drawnLinks[i];
				Color col;

				if (relPos.x == 0 && relPos.y == 0)
					continue;

				//Light up links from hovered tech
				uint alpha = 64;
				if (hovered)
					alpha = 255;

				// Pick correct color
				if (linkState[i])
					col = Color(alpha, 200, 255, 200);
				else
					col = Color(alpha, 255, 200, 200);

				if (even)
					relPos.y += 1;

				recti draw;
				switch(int(relPos.x)) {
					case -1:
						switch(int(relPos.y)) {
							case  0: draw = recti(0, 120, 242, 254); break;
							case  1: draw = recti(0, 254, 242, 390); break;
						}
					break;

					case 0:
						switch(int(relPos.y)) {
							case -1:
							case 0: draw = recti(240, 30, 270, 250); break;
							case 1:
							case 2: draw = recti(240, 260, 270, 475); break;
						}
					break;

					case 1:
						switch(int(relPos.y)) {
							case  0: draw = recti(270, 110, 514, 255); break;
							case  1: draw = recti(270, 255, 514, 390); break;
						}
					break;
				}

				if (draw.getSize().width == 0) {
					draw = recti(128, 128, 384, 384);
					col = Color(255, 255, 0, 0);
					continue;
				}

				drawTexture(link_lines, recti(drawPos+pos2di(ceil(draw.UpperLeftCorner.x*zoom), ceil(draw.UpperLeftCorner.y*zoom)),
							dim2di(draw.getWidth()*zoom, draw.getHeight()*zoom)), draw, col, true);
			}
		}

		clearDrawClip();
	}
	
	EventHandleState onEvent(const GUIEvent@ evt) {
		if(evt.EventType == GEVT_Focus_Gained) {
			if(evt.Caller.isAncestor(icon)) {
				ResearchWeb web;
				web.prepare(getActiveEmpire());
				if(shiftKey) {
					if(queue.queueIsEmpty)
						queue.queueActiveTech(web);
					queue.queueTechBeforeRepeat(descriptor);
				}
				else if(ctrlKey) {
					if(queue.queueIsEmpty)
						queue.queueActiveTech(web);
					queue.queueTech(descriptor);
				}
				else {
					web.setActiveTech(descriptor);
					if(!queue.queueIsEmpty)
						queue.queueTechFront(descriptor);
				}
				web.prepare(null);
				
				return EHS_Absorb;
			}
		}
		else if(evt.EventType == GEVT_Mouse_Over) {
			if(evt.Caller.isAncestor(icon)) {
				updateToolTip();
				@win.hoveredItem = this;
				hovered = true;

				if(useMomentaryLinks)
					showLinks();
			}
		}
		else if(@item != null) {
			if(evt.EventType == GEVT_Mouse_Left) {
				if(evt.Caller.isAncestor(icon)) {
					win.detailsBG.setVisible(false);
					hovered = false;
					if(useMomentaryLinks)
						hideLinks();
					return EHS_Handled;
				}
			}
		}
		else {
			if(evt.EventType == GEVT_Mouse_Left) {
				if(evt.Caller.isAncestor(icon)) {
					win.detailsBG.setVisible(false);
					hovered = false;
					if(useMomentaryLinks)
						hideLinks();
					return EHS_Handled;
				}
			}

		}
		
		//Check if the caller is our element
		if(evt.Caller.isAncestor(icon))
			return EHS_Handled;
		
		uint linkCount = links.length();
		for(uint i = 0; i < linkCount; ++i) {
			EventHandleState ehs = links[i].onEvent(evt);
			switch(ehs) {
				case EHS_Handled:
				case EHS_Absorb:
					return ehs;
			}
		}
		
		return EHS_Unhandled;
	}
	
	void showLinks() {
		uint linkCount = links.length();
		for(uint i = 0; i < linkCount; ++i)
			links[i].hover();
	}
	
	void hideLinks() {
		uint linkCount = links.length();
		for(uint i = 0; i < linkCount; ++i)
			links[i].unhover();
	}
	
	void generateLinks() {
		links.resize(0);
		uint linkCount = descriptor.linkCount;
		if(linkCount > 0) {
			float prevZoom = win.webView.getZoom();
			win.webView.setZoom(1.f, pos2di(0,0));
			const WebItem@ Item = @item;
			links.resize(linkCount);
			float linkAngle = 0, angleInc = 6.282f / float(linkCount), radius = 48.f + 16.f + 16.f;
			
			if(useMomentaryLinks)
				radius = 48.f + 9.f;
			
			pos2di iconCenter = icon.getPosition(); dim2di size = icon.getSize();
			iconCenter.x += size.width / 2;
			iconCenter.y += size.height / 2;
			
			bool smallLinks = linkCount > 6;
			for(uint i = 0; i < linkCount; ++i) {
				@links[i] = WebGridLink(iconCenter + pos2di(radius * cos(linkAngle),radius * sin(linkAngle)), this, i, smallLinks);
				linkAngle += angleInc;
			}
			win.webView.setZoom(prevZoom, pos2di(0,0));
			
			if(useMomentaryLinks)
				hideLinks();
		}
	}
	
	void update() {
		uint linkCount = links.length();
		for(uint i = 0; i < linkCount; ++i)
			links[i].update();

		if (@name != null) {
			if(@item == null)
				name.setColor(color_item_locked);
			else
				name.setColor(color_item_normal);

			bool textVisible = win.webView.getZoom() > 0.4f;
			name.setVisible(textVisible);
			level.setVisible(textVisible && !hovered);
		}

		if(item !is null) {
			float temp = 0.f, cost = 0.f, done = 0.f, lvl = 0.f;
			item.getLevels(lvl,done,cost,temp);

			info.progress = done / cost;

			int newLevel = int(lvl);
			if (newLevel != info.level) {
				level.setText(i_to_s(newLevel));
			}
			info.level = newLevel;
		}
	}

	void updateToolTip() {
		float level = 0, progress, cost, maxLevel; 
		if(@item != null)
			item.getLevels(level,progress,cost,maxLevel);

		uint tiecnt = descriptor.getTieCount();
		uint lowest = 0;
		uint nextUnlock = 0;
		string@ improves = null;
		string@ unlock = "";

		//Get all subsystems improved by this tech and 
		//the next subsystem to unlock
		for (uint i = 0; i < tiecnt; ++i) {
			const subSystemDef@ tie = descriptor.getTie(i);
			uint lvl = descriptor.getTieLevel(i);

			if(uint(level) >= lvl)
				if (@improves == null) {
					@improves = tie.getName();
				}
				else
					improves += ", "+tie.getName();
			else {
				if (lowest == 0 || lvl < lowest) {
					lowest = lvl;
					nextUnlock = i;
					unlock = tie.getName();
				}
				else if (lvl == lowest) {
					unlock += "\n"+tie.getName();
				}
				else continue;

				//Check for reverse ties
				uint revcnt = tie.getTieCount();
				for (uint j = 0; j < revcnt; ++j) {
					const WebItemDesc@ rev = tie.getTie(j);
					uint revlvl = tie.getTieLevel(j);

					unlock += "\n    #c:ccc#"+localize(j == 0?"#RW_With":"#RW_And")+"#c# #c:ccf#"+rev.name
						+"#c# #c:ccc#"+localize("#RW_AtLevel")+"#c# #c:faa#"+revlvl+"#c#";
				}
			}
		}

		if (!win.detailsBG.isVisible()) {
			pos2di mousePos = getMousePosition();
			float left = win.webView.getAbsolutePosition().UpperLeftCorner.x;
			float width = win.webView.getSize().width;

			pos2di pos = win.detailsBG.getPosition();
			if (mousePos.x - left < width / 2) {
				pos.x = width - win.detailsBG.getSize().width + 7;
				win.detailsBorder.setPosition(pos2di(0, 0));
			}
			else {
				pos.x = 7;
				win.detailsBorder.setPosition(pos2di(243, 0));
			}
			win.detailsBG.setPosition(pos);

		}
		win.detailsBG.setVisible(true);
		string@ text;

		if (@item != null) {
			win.detailsName.setText( "#font:frank_12##c:0d0#"+descriptor.name + " #c#("+localize("#RW_Level")+" " + level + ")#font#" );
			@text = descriptor.desc + "\n\n#c:ccc#"+localize("#RW_Cost")+": " + standardize(cost) +
				(" / "+localize("#RW_Done")+": " + standardize(progress)) + (" (" + round(100.f * progress / cost) + "%)#c#");
		}
		else {
			win.detailsName.setText( "#font:frank_12##c:f00#"+descriptor.name + " #c#("+localize("#RW_Locked")+")#font#" );
			@text = descriptor.desc + "\n\n#c:ccc#"+localize("#RW_Elsewhere")+"\n#c#";
		}

		if(@improves != null)
			text += "\n\n#c:4f0#"+localize("#RW_Improves")+":#c#\n"+improves;

		if(lowest != 0)
			text += "\n\n#c:ff4#"+localize("#RW_NextUnlock")+":#c#\n"+unlock;

		win.detailsText.setText(text);
	}

	EventReturn onKeyEvent(GuiElement@,const KeyEvent&) {
		return ER_Pass;
	}
	
	EventReturn onMouseEvent(GuiElement@,const MouseEvent&) {
		return ER_Pass;
	}
	
	EventReturn onGUIEvent(GuiElement@ ele, const GUIEvent& event) {
		return ER_Pass;
	}
};

class WebGridLink {
	GuiImage@ icon;
	string@ tooltip;

	GridInfo@ info;
	GuiScripted@ infoScripted;
	
	bool unlocked;

	bool isActive;
	bool hovered;
	
	const WebGridItem@ itemMaster;
	uint linkIndex;
	
	WebGridLink(const pos2di &in center, const WebGridItem@ Item, uint LinkIndex, bool smaller) {
		@itemMaster = @Item;
		linkIndex = LinkIndex;
		unlocked = false;
		hovered = false;
		isActive = false;

		@info = GridInfo();
		
		float progress, cost = 0;
		Item.item.getLinkLevels(linkIndex, progress, cost);
		
		int size = smaller ? 36 : 48;
		
		@icon = GuiImage(center - pos2di(size / 2,size / 2), "res_link_unknown", Item.win.webPlane);
		icon.setSize(dim2di(size,size));
		icon.setScaleImage(true);
		@tooltip = Item.descriptor.getLinkName(LinkIndex) + (" (" + standardize(round(cost)) + ")");
		icon.setAlignment(EA_Scale,EA_Scale,EA_Scale,EA_Scale);

		@infoScripted = GuiScripted(recti(pos2di(0, 0), icon.getSize()), info, icon);
		infoScripted.setAlignment(EA_Scale,EA_Scale,EA_Scale,EA_Scale);
	}

	void hover() {
		hovered = true;
		icon.setVisible(true);
	}

	void unhover() {
		hovered = false;
		icon.setVisible(isActive);
	}

	void deactive() {
		isActive = false;
		icon.setVisible(hovered);
	}

	void active() {
		isActive = true;
		icon.setVisible(true);
	}
	
	void update() {
		if(unlocked) {
			info.progress = 0;
			return; //TODO: Decide if we should handle this case
		}

		icon.setVisible((hovered || isActive) && itemMaster.win.webView.getZoom() > 0.3f);

		float progress = 0, cost = 1;
		itemMaster.item.getLinkLevels(linkIndex, progress, cost);
		info.progress = progress / cost;
		if(progress >= cost) {
			unlocked = true; //TODO: Get the icon, name, etc of the other end of the link, where valid
			const WebItem@ end = itemMaster.item.getLinkEnd(linkIndex);
			if(end is null) { //Dead end
				icon.setImage("res_link_deadend");
				@tooltip = localize("#RW_Dead_End");
			}
			else {
				icon.setImage(end.descriptor.icon);
				@tooltip = "Link to " + end.descriptor.name;
			}
		}
	}
	
	void updateToolTip() {
		if(unlocked)
			return;
		float progress, cost;
		itemMaster.item.getLinkLevels(linkIndex, progress, cost);
		if(progress > 1.f)
			@tooltip = itemMaster.item.descriptor.getLinkName(linkIndex) + ((" (" + standardize(progress)) + (" / " + standardize(cost) + ")"));
	}
	
	EventHandleState onEvent(const GUIEvent@ evt) {
		if (evt.Caller !is icon && evt.Caller !is infoScripted)
			return EHS_Unhandled;
		
		if(evt.EventType == GEVT_Focus_Gained && !unlocked) {
			ResearchWeb web;
			web.prepare(getActiveEmpire());
			if(shiftKey) {
				if(queue.queueIsEmpty)
					queue.queueActiveTech(web);
				queue.queueTechBeforeRepeat(itemMaster.descriptor, linkIndex);
			}
			if(ctrlKey) {
				if(queue.queueIsEmpty)
					queue.queueActiveTech(web);
				queue.queueTech(itemMaster.descriptor, linkIndex);
			}
			else {
				web.setActiveTech(itemMaster.descriptor,linkIndex);
				if(!queue.queueIsEmpty)
					queue.queueTechFront(itemMaster.descriptor, linkIndex);
			}
			web.prepare(null);
			
			return EHS_Absorb;
		}
		else if(evt.EventType == GEVT_Mouse_Over) {
			if(useMomentaryLinks) {
				icon.setVisible(true);
				hovered = true;
			}
			recti rect = icon.getAbsolutePosition();
			pos2di bgCorner = itemMaster.win.position;
			pos2di ttCorner(rect.LowerRightCorner.x + 3 - bgCorner.x, rect.UpperLeftCorner.y - bgCorner.y);
			itemMaster.win.linkDetails.setVisible(true);
			itemMaster.win.linkDetails.setPosition(ttCorner);
			updateToolTip();
			itemMaster.win.linkDetails.setText(tooltip);
		}
		else if(evt.EventType == GEVT_Mouse_Left) {
			if(useMomentaryLinks) {
				icon.setVisible(isActive);
				hovered = false;
			}
			itemMaster.win.linkDetails.setVisible(false);
		}
		return EHS_Handled;
	}
};
/* }}} */
/* {{{ Utilities */
string@ formatTime(int time, const string@ suffix) {
	if(time > 9)
		return time + suffix;
	else
		return "0" + time + suffix;
}

string@ formatETA(int eta) {
	if(eta < 0)
		return "Never";
	int secs, mins, hrs, days;
	string@ str;

	secs = eta % 60; eta = (eta - secs) / 60;
	mins = eta % 60; eta = (eta - mins) / 60;
	hrs = eta % 24; eta = (eta - hrs) / 24;
	days = eta;
	
	//Show two time ranges of interest
	if(days > 0)
		@str = days + "d:" + formatTime(hrs,"h");
	else if(hrs > 0)
		@str = hrs + "h:" + formatTime(mins,"m");
	else if(mins > 0)
		@str = mins + "m:" + formatTime(secs,"s");
	else
		@str = formatTime(secs,"s");
	
	return str;
}

void updateTicker(ResearchWeb& web) {
	int linkIndex = 0;
	const WebItem@ curTech = web.getActiveTech(linkIndex);
	string@ rateText = combine(localize("#rate"),": ", standardize(web.getResearchRate()));

	if(curTech is null) {
		web.setActiveTech( getWebItemDesc( rand(getWebItemDescCount()-1) ) );
	}
	else if(linkIndex < 0) {
		float level, progress, cost, maxLevel; curTech.getLevels(level,progress,cost,maxLevel);
		float resRate = web.getResearchRate();
		setTicker( curTech.descriptor.name + localize("#toLevel") + ftos_nice(level + 1), locale_eta + formatETA(resRate > 0 ? (cost - progress) / resRate : -1), rateText);
		setTickerPercent(cost > 0 ? progress / cost : 0, Color(0xff61c4ec));
	}
	else {
		float progress, cost; curTech.getLinkLevels( linkIndex, progress, cost );
		float resRate = web.getResearchRate();
		setTicker( curTech.descriptor.name + " - " + curTech.descriptor.getLinkName(linkIndex), locale_eta + formatETA(resRate > 0 ? (cost - progress) / resRate : -1), rateText);
		setTickerPercent(cost > 0 ? progress / cost : 0, Color(0xff61c4ec));
	}
}

//Queue End Notifier
//=========
GuiElement@ queueEndNotice;
int queueEndID;

void showQueueEndNotice() {
	if(queueEndNotice is null) {
		@queueEndNotice = GuiScripted( recti(pos2di(0,0),dim2di(16,16)), notification_icon("event_sheet",9), null );
		queueEndNotice.setToolTip(localize("#RW_QueueFinished"));
		queueEndNotice.setID(queueEndID);
		showEventIndicator(queueEndNotice);
		playSound("queue_finish");
	}
}

void OnNotificationAccept(notification_icon@ ico) {
	openResearchWindow();
	hideEventNotifiers();
}

void OnNotificationDismiss(notification_icon@ ico) {
	hideEventNotifiers();
}

void hideEventNotifiers() {
	if(queueEndNotice is null)
		return;
	hideEventIndicator(queueEndNotice);
	queueEndNotice.remove();
	@queueEndNotice = null;
}
//=========
/* }}} */
// {{{ Research Automation
bool automateResearch = true;
const WebItem@ watchTech = null;
float goalLevel = 0;

const WebItem@ getLowestAvailableTech(ResearchWeb& web) {
	float lowest = -1;
	const WebItem@ lowestItem = null;

	uint cnt = getWebItemDescCount();
	for (uint i = 0; i < cnt; ++i) {
		const WebItemDesc@ desc = getWebItemDesc(i);

		if (web.isTechVisible(desc)) {
			const WebItem@ item = web.getItem(desc);

			if (item.level < lowest || lowest < 0) {
				@lowestItem = item;
				lowest = item.level;
			}
		}
	}
	return lowestItem;
}

void updateAutomation(ResearchWeb& web) {
	if (!automateResearch) {
		@watchTech = null;
		return;
	}

	if (!queue.queueIsEmpty) {
		@watchTech = null;
		return;
	}

	int link = -1;
	const WebItem@ activeTech = web.getActiveTech(link);

	if (activeTech !is watchTech) {
		if (link >= 0) {
			@watchTech = null;
			return;
		}
		else {
			if (watchTech !is null) {
				@watchTech = activeTech;
				goalLevel = watchTech.level + 1;
				web.setActiveTech(watchTech.descriptor);
				return;
			}
		}
	}

	bool change = true;
	if (watchTech !is null)
		change = watchTech.level >= goalLevel;

	if (change) {
		@watchTech = getLowestAvailableTech(web);
		goalLevel = watchTech.level + 1;
		web.setActiveTech(watchTech.descriptor);
	}
}
// }}}

void openResearchWindow() {
	hideEventNotifiers();
	removeAllTechNotices();
	wins[0].setVisible(true);
}

void createResearchWindow() {
	uint n = wins.length();
	wins.resize(n+1);
	@wins[n] = ResearchWindowHandle(makeScreenCenteredRect(defaultSize));
	wins[n].bringToFront();
}

void closeResearchWindow(ResearchWindow@ win) {
	int index = findResearchWindow(win);
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

GuiElement@ getResearchWindow() {
	if (wins.length() == 0)
		return null;
	return wins[0].ele;
}

void toggleResearchWindow() {
	bool anyVisible = false;
	for (uint i = 0; i < wins.length(); ++i)
		if (wins[i].isVisible())
			anyVisible = true;
	toggleResearchWindow(!anyVisible);
}

void toggleResearchWindow(bool show) {
	if (shiftKey) {
		createResearchWindow();
	}
	else {
		// Toggle all windows to a particular state
		for (uint i = 0; i < wins.length(); ++i) {
			wins[i].setVisible(show);
			if (show)
				wins[i].bringToFront();
		}
		if (show)
			hideEventNotifiers();
	}
}

bool ToggleResearchWin(const GUIEvent@ evt) {
	if (evt.EventType == GEVT_Clicked) {
		toggleResearchWindow();
		return true;
	}
	return false;
}

bool ToggleResearchWin_key(uint8 flags) {
	if (flags & KF_Pressed != 0) {
		toggleResearchWindow();
		return true;
	}
	return false;
}

int findResearchWindow(ResearchWindow@ win) {
	for (uint i = 0; i < wins.length(); ++i)
		if (wins[i].script is win)
			return i;
	return -1;
}

ResearchQueue@ queue;
ResearchWindowHandle@[] wins;

GuiButton@ rw_restore_rw;

dim2di defaultSize;

int getQueueSize() {
	return queue.queueList.length();
}

void setResVisible(bool vis) {
	rw_restore_rw.setVisible(vis);
}

void init() {
	// Initialize some constants
	initSkin();
	color_item_locked = Color(255, 100, 100, 100);
	color_item_normal = Color(255, 255, 255, 255);

	@link_lines = getMaterialTexture("res_lines");
	@item_overlay = getMaterialTexture("res_web_overlay");

	@locale_eta = localize("#RW_ETA");
	@locale_res_rate = localize("#RW_RES_RATE");
	@locale_zoom = localize("#RW_Zoom");
	@locale_level = localize("#level")+" ";

	queueEndID = reserveGuiID();

	// Create queue system
	@queue = ResearchQueue();

	// Figure out default size of research window
	int xres = getScreenWidth(), yres = getScreenHeight();

	if (xres >= 1280 && yres >= 1024)
		defaultSize = dim2di(1024, 767);
	else if (yres >= 800)
		defaultSize = dim2di(920, 501);
	else
		defaultSize = dim2di(920, 397);

	// Toggle key
	bindFuncToKey("F5", "script:ToggleResearchWin_key");

	// Topbar button
	@rw_restore_rw = GuiButton(recti(pos2di(xres / 2 + 150, 0), dim2di(100, 25)), null, null);
	rw_restore_rw.setSprites("TB_Research", 0, 2, 1);
	rw_restore_rw.setAppearance(BA_UseAlpha, BA_Background);
	rw_restore_rw.setAlignment(EA_Center, EA_Top, EA_Center, EA_Top);
	bindGuiCallback(rw_restore_rw, "ToggleResearchWin");

	// Create initial window
	wins.resize(1);
	@wins[0] = ResearchWindowHandle(makeScreenCenteredRect(defaultSize));
	wins[0].setVisible(false);
}

void tick(float time) {
	{
		ResearchWeb web;
		web.prepare(getActiveEmpire());
		bool anyVisible = false;

		// Trigger research automation
		updateAutomation(web);

		// Update windows
		for (uint i = 0; i < wins.length(); ++i) {
			if (wins[i].isVisible()) {
				wins[i].update(web, time);
				anyVisible = true;
			}
		}

		// Update ticker
		updateTicker(web);

		// Show message
		if (!anyVisible) {
			if(!queue.queueIsEmpty) {
				queue.update(web);
				
				if(queue.queueIsEmpty)
					showQueueEndNotice();
			}
		}
		else {
			queue.update(web);
		}
	}
}
