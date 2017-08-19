// map_generation
// ==============
// Maps can refer to the functions in this file in order to let the game / mod decide 
// how to build their systems, leaving maps to do positioning.

// {{{ Imports
import void initSpecialSystems() from "special_systems";
import System@ makeSpecialSystem(Galaxy@, vector) from "special_systems";
// }}}
// {{{ Constants
// Strings
string@ strOre = "DeepOre", strDmg = "Damage", strMoonEx = "moon", strRingEx = "natural_ring", strComet = "comet", strAsteroid = "asteroid", strHydrogen = "hydrogen";
string@ strOrbPitch = "orb_disc_pitch", strOrbEcc = "orb_eccentricity", strOrbDays = "orb_days_per_year", strOrbRad = "orb_radius", strOrbMass = "orb_mass";
string@ strOrbPosInYear = "orb_year_pos", strOrbYaw = "orb_disc_yaw", strMass = "mass";
string@ strRadius = "radius";
string@ strLivable = "Livable";

// Settings
float minPlanetRadius = 11.f, maxPlanetRadius = 19.f;
float orbitRadiusFactor = 200.f;
float tempFalloffRadius  = orbitRadiusFactor * 6.f;
float maxStructSpace = 25.5f;
float starSizeFactor = 2.5f;
const float starMassFactor = 1.f / 11000.f;
bool makeOddities = true;
bool prepped = false;
bool balancedStart = false;
bool specialSystems = true;
bool tempFalloff = true;
int specialNum = 40;
float allyDist = 0.1f;
float playerDist = 0.4f;

void setMakeOddities(bool make) { makeOddities = make; }
bool getMakeOddities() { return makeOddities; }
float getOrbitRadiusFactor() { return orbitRadiusFactor; }

// Mathematical
const float Pi    = 3.14159265f;
const float twoPi = 6.28318531f;

// Descriptors
Oddity_Desc comet_desc, asteroid_desc;
Planet_Desc plDesc;
System_Desc sysDesc;
Star_Desc starDesc;
Orbit_Desc orbDesc;

void setOrbitDesc(Orbit_Desc& orb) {
	orbDesc.set(orb);
}

int[] ColdTypes;
int[] NormalTypes;
int[] WarmTypes;
int[] LavaTypes;
int[] GasTypes;

void initPlanetType(int[]& arr, string@ tag) {
	uint cnt = getPlanetTypeCount();
	for (uint i = 0; i < cnt; ++i) {
		const PlanetType@ tp = getPlanetType(i);
		if (tp.hasTag(tag)) {
			uint n = arr.length();
			arr.resize(n+1);
			arr[n] = tp.id;
		}
	}
}

int getRandomType(int[]& arr) {
	return arr[rand(0, arr.length() - 1)];
}

void initPlanetTypes() {
	initPlanetType(ColdTypes, "ice");
	initPlanetType(NormalTypes, "terran");
	initPlanetType(WarmTypes, "desert");
	initPlanetType(LavaTypes, "lava");
	initPlanetType(GasTypes, "gas");
}

// }}}
// {{{ Helper utilities
// Prepares global for use
void initMapGeneration() {
	if (!prepped) {
		comet_desc.id = strComet;
		asteroid_desc.id = strAsteroid;
		balancedStart = getGameSetting("MAP_BALANCED_START",0) != 0.f;

		allyDist = getGameSetting("MAP_ALLY_DIST", 0.15f);
		playerDist = getGameSetting("MAP_PLAYER_DIST", 0.45f);
		tempFalloff = getGameSetting("MAP_TEMP_FALLOFF", 1.f) > 0.5f;

		specialSystems = getGameSetting("MAP_SPECIAL_SYSTEMS",1) != 0.f;
		float specialDens = getGameSetting("MAP_SPECIAL_SYSTEM_DENSITY", 0.025f);
		if (specialDens <= 0)
			specialSystems = false;
		else
			specialNum = int(round(1.f/specialDens));
		initSpecialSystems();

		initPlanetTypes();

		prepped = true;
	}
}

//Turns pct into low at <=0, high at >=1, and a linear interpolation in between
float range(float low, float high, float pct) {
	return low + (clamp(0.f, 1.f, pct) * (high-low));
}

// Returns the percentage that x is between low and high
float pctBetween(float x, float low, float hi) {
	if(x <= low)
		return 0.f;
	else if(x >= hi)
		return 1.f;
	return (x - low)/(hi - low);
}

// Adds a structure to a planet by name
void addStruct(uint count, string@ name, Planet@ pl) {
	const subSystemDef@ struct = getSubSystemDefByName(name);
	if(struct is null)
		return;
	for(uint i = 0; i < count; ++i)
		pl.addStructure(struct);
}

// Get a random planet from a system
set_int disregardPlanets;
Planet@ getRandomPlanet(System@ sys) {
	Empire@ space = getEmpireByID(-1);
	SysObjList objects;
	objects.prepare(sys);

	Planet@[] planets;
	int planetCount = 0;

	for (uint i = 0; i < objects.childCount; ++i) {
		Object@ obj = objects.getChild(i);
		Planet@ pl = obj;

		if (@pl != null) {
			if (obj.getOwner() is space && !disregardPlanets.exists(obj.uid)) {
				planets.resize(planetCount+1);
				@planets[planetCount] = pl;
				++planetCount;
			}
		}
		else if (@obj.toStar() == null)
			break;
	}

	objects.prepare(null);

	if (planetCount == 0)
		return null;
	else
		return planets[rand(planetCount - 1)];
}
// }}}
// {{{ Planet Generation
Planet@ makeRandomPlanet(System@ sys, uint plNum, uint plCount) {
	// Make a planet in the system
	return makeStandardPlanet(sys, plNum, plCount);
}

// {{{ Homeworld Generation
int[] playerTeams;
vector[] playerPositions;
Planet@ setupStandardHomeworld(System@ sys, Empire@ emp) {
	if(!emp.isValid() || emp.ID < 0)
		return null;

	Empire@ space = getEmpireByID(-1);
	Planet@ planet = null;
	
	int team = int(emp.getStat("Team"));
	int redos = 50;
	int pass = 4;
	do {
		Planet@ newPlanet = getRandomPlanet(sys);
		bool livable = sys.toObject().getStat(space, strLivable) > 0.1f;

		if (pass > 0 && livable) {
			// Player distance
			float glxRadius = getGalaxy().toObject().radius;
			float minPlayerDist = 1.f * glxRadius * 2.f;
			float maxAllyDist = 0.f;
			float fuzz = 1.f / float(5 - pass);
			vector pos = sys.toObject().getPosition();

			uint playerCnt = playerTeams.length();
			for (uint i = 0; i < playerCnt; ++i) {
				int otherTeam = playerTeams[i];
				float otherDist = playerPositions[i].getDistanceFrom(pos);

				if (otherTeam == team && team != 0)
					maxAllyDist = max(maxAllyDist, otherDist);
				else
					minPlayerDist = min(minPlayerDist, otherDist);
			}

			livable = (minPlayerDist > playerDist * glxRadius * 2.f * fuzz)
					&& (maxAllyDist < allyDist * glxRadius * 2.f * fuzz);
		}

		if(livable && !(newPlanet is null)) {
			@planet = @newPlanet;
			break;
		}
		System@ newSys = getRandomSystem();
		if(newSys is null)
			continue;
		@sys = @newSys;
		@planet = @newPlanet;

		if (pass >= 0 && redos == 1) {
			if (pass == 1)
				warning("Couldn't find a fitting system for "+emp.getName()+" in the first passes.");
			redos = 25;
			pass -= 1;
		}
	} while(redos-- > 0);

	// Record this player's position
	uint n = playerTeams.length();
	playerTeams.resize(n+1);
	playerPositions.resize(n+1);
	playerTeams[n] = team;
	playerPositions[n] = sys.toObject().getPosition();

	Orbit_Desc orbDesc;
	
	sys.toObject().setStat(space, strLivable, 0.f);
	Planet_Desc plDesc;
	plDesc.PlanetRadius = randomf(9.f,11.f);
	plDesc.RandomConditions = false;
	string@ name = "";

	orbDesc.Eccentricity = 1.f;
	if (planet is null) {
		// Just creating a new planet, this may cause colliding planet syndrome
		orbDesc.Radius = randomf(2.f, 6.f) * orbitRadiusFactor;
	}
	else {
		// We are swapping a random planet from the system with our own
		orbDesc.Radius = planet.getOrbitRadius();

		Object@ plObj = planet.toObject();
		disregardPlanets.insert(plObj.uid);
		name += plObj.getName();

		// Destroy the planet without showing an explosion
		planet.eradicate();
	}
	
	//Uncomment to force the homeworld to a specific type
	//plDesc.setPlanetType( getPlanetTypeID( "rock2" ));
	
	//Setup orbit information based on the star
	SysObjList children; children.prepare(sys);
	if(children.childCount > 0) {
		Object@ child = children.getChild(0);
		Star@ star = @child;
		if(@star != null) {
			if(orbDesc.Radius < child.radius * 1.5f)
				orbDesc.Radius = max(child.radius * randomf(1.5f,2.2f), 2.f * orbitRadiusFactor);
			//Set planet orbit information for this star
			orbDesc.MassRadius = child.radius;
			orbDesc.Mass = child.radius * starMassFactor;
		}
	}
	children.prepare(null);

	plDesc.setOrbit(orbDesc);
	Planet@ pl = sys.makePlanet(plDesc);
	pl.setStructureSpace(maxStructSpace);
	Object@ obj = pl.toObject();
	obj.setOwner(emp);

	if (name != "")
		obj.setName(name);

	obj.getState("Damage").max = 1000000000.f * randomf(10.f, 50.f);

	State@ ore = obj.getState("DeepOre");
	ore.max = 50000000.f;
	ore.val = 50000000.f;

	string@ strFarm = "Farm";
	if(emp.hasTraitTag("no_food"))
		if(emp.hasTraitTag("consume_metals"))
			strFarm = "MetalMine";
		else
			strFarm = "City";

	string@ strGoods = "GoodsFactory";
	if(emp.hasTraitTag("forever_indifferent"))
		strGoods = "MetalMine";
	
	string@ strSpacePort = "SpacePort";
	if(emp.hasTraitTag("nobank"))
		strSpacePort = "ShipYard";
	
	//Setup starting structures
	addStruct(1, "GalacticCapital", pl);

	if (!emp.hasTraitTag("empty_homeworld")) {
		addStruct(1, "MetalMine", pl);
		addStruct(2, "City", pl);
		addStruct(3, "MetalMine", pl);
		addStruct(3, "ElectronicFact", pl);
		addStruct(3, "AdvPartFact", pl);
		addStruct(2, "City", pl);
		addStruct(2, "SciLab", pl);
		addStruct(1, "City", pl);
		addStruct(1, strFarm, pl);
		addStruct(1, strGoods, pl);
		addStruct(1, strSpacePort, pl);
		addStruct(1, "ShipYard", pl);

		if (emp.hasTraitTag("larger_homeworld")) {
			pl.setStructureSpace(maxStructSpace + 10);

			addStruct(3, "City", pl);
			addStruct(1, strGoods, pl);
			addStruct(4, "MetalMine", pl);
			addStruct(3, "ElectronicFact", pl);
			addStruct(3, "AdvPartFact", pl);

			@ore = obj.getState("DeepOre");
			ore.val = ore.val / 2.f;
		}
	}

	if (emp.hasTraitTag("mined_homeworld")) {
		@ore = obj.getState("DeepOre");
		emp.addStat("Metals", ore.val * 0.05f);
		ore.val = 0.f;
	}
	
	//Start the planet with 92% of max population
	pl.modPopulation(pl.getMaxPopulation() * 0.92f);
	
	//Start the planet with 75% stores of economic resources
	State@ s_m = obj.getState("Metals"); s_m.val = s_m.max * 0.75f;
	State@ s_e = obj.getState("Electronics"); s_e.val = s_e.max * 0.75f;
	State@ s_a = obj.getState("AdvParts"); s_a.val = s_a.max * 0.75f;

	if (emp.hasTraitTag("second_planet"))
		createSecondaryPlanet(sys, emp);
	
	return pl;
}

void createSecondaryPlanet(System@ sys, Empire@ emp) {
	// Find the first planet in the system
	SysObjList objs;
	Planet@ planet = null;
	objs.prepare(sys);

	Orbit_Desc orbDesc;
	for (uint i = 0; i < objs.childCount; ++i) {
		Object@ child = objs.getChild(i);
		Star@ star = child;
		Planet@ pl = child;

		if (star !is null) {
			if(orbDesc.Radius < child.radius * 1.5f)
				orbDesc.Radius = max(child.radius * randomf(1.5f,2.2f), 2.f * orbitRadiusFactor);
			//Set planet orbit information for this star
			orbDesc.MassRadius = child.radius;
			orbDesc.Mass = child.radius * starMassFactor;
		}
		else if (pl !is null) {
			if (!child.getOwner().isValid() && !disregardPlanets.exists(child.uid)) {
				@planet = pl;
				break;
			}
		}
	}

	// Create a new planet if we didn't find any
	if (planet is null) {
		Planet_Desc plDesc;
		plDesc.PlanetRadius = randomf(9.f,11.f);
		plDesc.RandomConditions = false;

		orbDesc.IsStatic = false;
		orbDesc.Radius = randomf(2.f, 5.f) * orbitRadiusFactor;
		plDesc.setOrbit(orbDesc);

		Planet@ planet = sys.makePlanet(plDesc);
	}

	disregardPlanets.insert(planet.toObject().uid);

	// Set correct data on planet
	Object@ obj = planet;
	planet.setStructureSpace(15);
	obj.setOwner(emp);

	while (planet.getConditionCount() > 0) {
		const PlanetCondition@ cond = planet.getCondition(0);
		planet.removeCondition(cond.get_id());
	}

	State@ ore = obj.getState("DeepOre");
	ore.max = 50000000.f;
	ore.val = 50000000.f;

	obj.getState("Damage").max = 1000000000.f * randomf(6.f, 20.f);

	// Which farm to use?
	string@ strFarm = "Farm";
	if (emp.hasTraitTag("no_food"))
		if (emp.hasTraitTag("consume_metals"))
			strFarm = "MetalMine";
		else
			strFarm = "City";

	addStruct(1, "Capital", planet);
	addStruct(1, "MetalMine", planet);
	addStruct(2, "City", planet);
	addStruct(2, "MetalMine", planet);
	addStruct(2, "ElectronicFact", planet);
	addStruct(3, "AdvPartFact", planet);
	addStruct(2, "City", planet);
	if(!emp.hasTraitTag("nobank"))
		addStruct(1, "SpacePort", planet);
	else
		addStruct(1, "ShipYard", planet);
	addStruct(1, strFarm, planet);

	planet.modPopulation(planet.getMaxPopulation() * 0.92f);
	State@ s_m = obj.getState("Metals"); s_m.val = s_m.max * 0.75f;
	State@ s_e = obj.getState("Electronics"); s_e.val = s_e.max * 0.75f;
	State@ s_a = obj.getState("AdvParts"); s_a.val = s_a.max * 0.75f;
}
// }}}
// {{{ Standard Planet
Planet@ makeStandardPlanet(System@ sys, uint plNum, uint plCount) {
	// Planet radius
	float pRad = randomf(minPlanetRadius, maxPlanetRadius), pVol = pRad * pRad * pRad * 4.189f;
	plDesc.PlanetRadius = pRad;
	plDesc.RandomConditions = false;

	// Calculate planetary temperature
	if (tempFalloff) {
		int type = -1;
		float temp = starDesc.Temperature / sqr(orbDesc.Radius / tempFalloffRadius);
		float tp = randomf(1.f);

		if (tp < 0.15f)
			type = getRandomType(GasTypes);
		else if (tp < 0.2f)
			type = getRandomType(LavaTypes);
		else if (temp > 19000.f)
			type = getRandomType(WarmTypes);
		else if (temp > 7000.f)
			type = getRandomType(NormalTypes);
		else
			type = getRandomType(ColdTypes);

		plDesc.setPlanetType(type);
	}

	// Planet orbit
	plDesc.setOrbit(orbDesc);
	
	// Create planet
	Planet@ pl = sys.makePlanet(plDesc);
	pl.setStructureSpace((pctBetween(pRad, minPlanetRadius, maxPlanetRadius) * 0.5f + 0.5f) * maxStructSpace);
	
	Object@ planet = pl.toObject();

	// Add random conditions
	if (randomf(1.f) < 0.6f)
		pl.addPositiveCondition();
	else
		pl.addNegativeCondition();

	if (randomf(1.f) < 0.5f) {
		if (randomf(1.f) < 0.6f)
			pl.addPositiveCondition();
		else
			pl.addNegativeCondition();
	}
	
	// Give the planet ore
	State@ ore = planet.getState(strOre);
	ore.max = pVol * 6000.f;
	ore.val = ore.max * (0.5f + randomf(0.5f));
	
	planet.getState(strDmg).max = pVol * 1000000.f;
	
	// Add moons
	uint moons = 0;
	while(randomf(1.f) < 0.35f && moons < 6) {
		moons++;
		pl.addExtension(strMoonEx);
	}
	
	// Add ring
	if(moons == 0 && randomf(1.f) < 0.35f) {
		pl.addExtension(strRingEx);
	}

	return pl;
}
// }}}
// }}}
// {{{ Oddity Generation
// {{{ Comet
void makeRandomComet(System@ sys) {
	comet_desc.clear();
	
	float baseRadius = randomf(1.0f,1.8f) * orbitRadiusFactor;
	
	comet_desc.setFloat(strOrbRad, baseRadius);
	comet_desc.setFloat(strOrbMass, 5.f);
	Object@ comet = sys.makeOddity(comet_desc);
	
	State@ H2 = comet.getState(strHydrogen);
	H2.max = randomf(10000.f,25000.f);
	H2.val = H2.max;
}
// }}}
// {{{ Asteroids
void makeRandomAsteroid(System@ sys, uint rocks) {
	asteroid_desc.clear();
	
	asteroid_desc.setFloat(strOrbMass, 0.2f); //Slow down the orbit
	asteroid_desc.setFloat(strOrbEcc, randomf(0.9f,1.1f));
	
	float maxRadius = sys.toObject().radius * 0.8f;
	float baseRadius = randomf(2.f,6.f) * orbitRadiusFactor, rockMaxDev = orbitRadiusFactor / 4.f;
	float basePitch = randomf(-0.2f,0.2f), rockPitchDev = 10.f / (2.f * twoPi * baseRadius);
	
	for(uint i = 0; i < rocks; ++i) {
		asteroid_desc.setFloat(strOrbDays, randomf(3.f, 6.f));
		asteroid_desc.setFloat(strRadius, randomf(4.f, 8.f));
		asteroid_desc.setFloat(strOrbYaw, twoPi * randomf(-0.4f,0.4f) / float(rocks));
		
		float rockDev = randomf(rockMaxDev), rockDevAng = randomf(twoPi);
		float oreVal = randomf(3000000, 9000000);
		
		asteroid_desc.setFloat(strOrbRad, min(baseRadius + (rockDev * cos(rockDevAng)), maxRadius));
		asteroid_desc.setFloat(strOrbPitch, basePitch + (rockDev * rockPitchDev * sin(rockDevAng)));
		asteroid_desc.setFloat(strMass, oreVal);
		
		Object@ asteroid = sys.makeOddity(asteroid_desc);
		
		State@ ore = asteroid.getState(strOre);
		ore.max = oreVal;
		ore.val = oreVal;
		
		State@ hp = asteroid.getState(strDmg);
		hp.val = 0;
		hp.max = oreVal;
	}
}
// }}}
// }}}
// {{{ System Generation
System@ makeRandomSystem(Galaxy@ Glx, vector position, uint sysNum, uint sysCount) {
	// Create system sysNum/sysCount at position
	float sysType = randomf(100.f);

	if (specialSystems && specialNum > 0 && sysNum > 0 && sysNum % specialNum == 0) {
		System@ sys = makeSpecialSystem(Glx, position);
		if (sys !is null)
			return sys;
	}

	if (sysNum >= 11) {
		// We can have dead systems when we already
		// have 11 live ones (one for each possible player)
		if(sysType >= 97)
			return makeSupernova(Glx, position);
		else if (sysType >= 90)
			return makeBinarySystem(Glx, position);
		else if (sysType >= 83 && makeOddities)
			return makeAsteroidBelt(Glx, position);
		else
			return makeStandardSystem(Glx, position);
	}
	else {
		// Guaranteed live systems
		if (sysType >= 90)
			return makeBinarySystem(Glx, position);
		else
			return makeStandardSystem(Glx, position);
	}
}

// {{{ Standard System
System@ makeStandardSystem(Galaxy@ glx, vector pos) {
	// Reset orbit parameters
	orbDesc.Offset = vector(0, 0, 0);
	orbDesc.setCenter(null);
	orbDesc.PosInYear = -1.f;
	orbDesc.IsStatic = true;

	// Create the system
	sysDesc.Position = pos;
	sysDesc.AutoStar = false;

	System @sys = @glx.createSystem(sysDesc);

	// Create the star
	starDesc.Temperature = randomf(2000,21000);
	starDesc.Radius = randomf(30.f + (starDesc.Temperature / 1000.f),60.f + (starDesc.Temperature / 600.f)) * starSizeFactor;
	starDesc.Brightness = 1;
	starDesc.setOrbit(orbDesc);
	
	sys.makeStar(starDesc);

	// Set planet orbit parameters
	orbDesc.MassRadius = starDesc.Radius;
	orbDesc.Mass = starDesc.Radius * starMassFactor;
	orbDesc.Radius = orbitRadiusFactor;
	orbDesc.IsStatic = false;

	int pCount = rand(1, 3) + rand(1, 3);
	
	for(int p = 0; p < pCount; ++p) {
		orbDesc.Radius += randomf(1.f, 2.5f) * orbitRadiusFactor;
		orbDesc.Eccentricity = randomf(0.5f, 1.5f);

		makeRandomPlanet(sys, p, pCount);
	}
	
	if(!balancedStart || (pCount > 2 && pCount < 5))
		sys.toObject().setStat(getEmpireByID(-1), strLivable, 1.f);

	// Add oddities to system
	if(makeOddities) {
		int comets = 1;
		while (randomf(1.f) < (0.60f / comets)) {
			makeRandomComet(sys);
			++comets;
		}
		
		int belts = 0;
		while (randomf(1.f) < 1.f / (belts + 3.f) && belts < pCount) {
			makeRandomAsteroid(sys, rand(20,50));
			++belts;
		}
	}

	return sys;
}
// }}}
// {{{ Binary System
System@ makeBinarySystem(Galaxy@ glx, vector pos) {
	// Create the system
	sysDesc.Position = pos;
	sysDesc.AutoStar = false;

	System @sys = @glx.createSystem(sysDesc);
	sys.toObject().setStat(getEmpireByID(-1), strLivable, 1.f);

	// Star details
	starDesc.Brightness = 1;

	// Orbit details
	float orbOffset = 40.f;
	float orbRadius = 130.f;
	orbDesc.Eccentricity = 0.5f;

	orbDesc.Mass = 16.f;
	orbDesc.MassRadius = 8.f;
	orbDesc.Radius = orbRadius;
	orbDesc.Yaw = randomf(twoPi);

	// Create the primary star
	orbDesc.PosInYear = 0.f;
	orbDesc.Offset = vector(-orbOffset, 0, 0);
	starDesc.Temperature = randomf(2000,21000);
	starDesc.Radius = randomf(70.f, 110.f);
	starDesc.setOrbit(orbDesc);
	
	float primaryRadius = starDesc.Radius;
	Star@ primary = sys.makeStar(starDesc);

	// Create the secondary star
	orbDesc.PosInYear = 0.5f;
	orbDesc.Offset = vector(orbOffset, 0, 0);
	starDesc.Temperature = randomf(2000,21000);
	starDesc.Radius = randomf(70.f, 110.f);
	starDesc.setOrbit(orbDesc);
	
	float secondaryRadius = starDesc.Radius;
	Star@ secondary = sys.makeStar(starDesc);

	// Set planet orbit parameters
	orbDesc.Yaw = 0.f;
	orbDesc.MassRadius = starDesc.Radius * starSizeFactor;
	orbDesc.Mass = starDesc.Radius * starMassFactor * starSizeFactor;
	orbDesc.Radius = orbitRadiusFactor * 2.5f;
	orbDesc.PosInYear = -1.f;
	orbDesc.Offset = vector(0, 0, 0);

	int pCount = rand(1, 3) + rand(1, 2);
	
	for(int p = 0; p < pCount; ++p) {
		orbDesc.Radius += randomf(1.f, 2.5f) * orbitRadiusFactor;
		orbDesc.Eccentricity = randomf(0.5f, 1.5f);

		makeRandomPlanet(sys, p, pCount);
	}

	orbDesc.setCenter(null);
	orbDesc.PosInYear = -1.f;

	// Add oddities to system
	if(makeOddities) {
		int belts = 0;
		while (randomf(1.f) < 1.f / (belts + 3.f) && belts < pCount) {
			makeRandomAsteroid(sys, rand(20,50));
			++belts;
		}
	}

	return sys;
}
// }}}
// {{{ Asteroid belt
System@ makeAsteroidBelt(Galaxy@ glx, vector pos) {
	// Create the system
	System@ sys;
	sysDesc.Position = pos;
	sysDesc.AutoStar = false;

	float maxRad = randomf(3.f, 8.f) * orbitRadiusFactor;
	sysDesc.StartRadius = 1.5f * maxRad;
	
	@sys = @glx.createSystem(sysDesc);

	// Create the asteroids
	asteroid_desc.clear();
	asteroid_desc.setFloat(strOrbMass, 0.1f); //Slow down the orbit

	uint rocks = rand(15, 25) * round(maxRad / orbitRadiusFactor);
	float radius;
	
	for(uint i = 0; i < rocks; ++i) {
		if (i == 0)
			radius = 140.f;
		else if (i % 10 == 0)
			radius = randomf(30.f, 90.f);
		else
			radius = randomf(6.f, 30.f);

		float oreVal = randomf(25000.f, 26000.f) * radius * radius;
		asteroid_desc.setFloat(strMass, oreVal);

		asteroid_desc.setFloat(strRadius, radius);
		asteroid_desc.setFloat(strOrbYaw, randomf(twoPi));
		asteroid_desc.setFloat(strOrbEcc, randomf(0.9f,1.1f));
		asteroid_desc.setFloat(strOrbPitch, randomf(-0.4f, 0.4f));
		
		if (i == 0) {
			asteroid_desc.setFloat(strOrbRad, 0.01f);
			asteroid_desc.setFloat(strOrbMass, 0.0001f); //Slow down the orbit
			asteroid_desc.setFloat(strOrbDays, 0.f);
		}
		else {
			asteroid_desc.setFloat(strOrbRad, 160.f + randomf(1.2f) * (maxRad - 160.f));
			asteroid_desc.setFloat(strOrbMass, 0.1f); //Slow down the orbit
			asteroid_desc.setFloat(strOrbDays, randomf(3.f, 6.f));
		}
		
		Object@ asteroid = sys.makeOddity(asteroid_desc);

		if (i == 0)
			asteroid.setGlobalVisibility(true);
		
		State@ ore = asteroid.getState(strOre);
		ore.max = oreVal;
		ore.val = oreVal;
		
		State@ hp = asteroid.getState(strDmg);
		hp.val = 0;
		hp.max = oreVal;
	}
	return sys;
}
// }}}
// {{{ Supernova System
System@ makeSupernova(Galaxy@ glx, vector pos) {
	System@ sys;
	{
		sysDesc.Position = pos;
		sysDesc.AutoStar = false;
		
		@sys = @glx.createSystem(sysDesc);
	}
	
	{
		starDesc.Temperature = randomf(1000,4000);
		starDesc.Radius = randomf(180,270) * starSizeFactor;
		starDesc.Brightness = 1;
		starDesc.clearOrbit();
		
		sys.makeStar(starDesc);
	}

	return sys;
}
// }}}
// {{{ Quasar System
// The Quasar is special in that it outputs a float with the minimum
// distance from the quasar that systems should be generated at
float makeQuasar(Galaxy@ glx, vector pos, float sizeFactor) {
	System@ sys;
	{
		sysDesc.Position = pos;
		sysDesc.AutoStar = false;
		
		@sys = @glx.createSystem(sysDesc);
	}
	
	{
		starDesc.Temperature = randomf(40000,80000);
		starDesc.Radius = randomf(400,450) * sizeFactor * starSizeFactor;
		starDesc.Brightness = 8;
		starDesc.clearOrbit();
		
		Star@ quasar = sys.makeStar(starDesc);

		Effect quasarExplosion("Quasar");
		quasar.toObject().addTimedEffect(quasarExplosion, pow(10, 35), 0.f,
				quasar.toObject(), null, null, TEF_None);
		
		return starDesc.Radius * 3.f;
	}
}
// }}}
// }}}

