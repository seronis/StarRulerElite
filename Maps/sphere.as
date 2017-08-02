//sphere
//======
//Creates a sphere with systems positioned at random inside it

#include "/include/map_lib.as"
#include "/include/sphere_gas.as"

void makeMap(Galaxy@ Glx) {
	prepMap();
	
	uint sysCount = getGameSetting("SYSTEM_COUNT",150);
	float maxRad = sqrt(sysCount) * getGameSetting("MAP_SYSTEM_SPACING", 3000.f) * orbitRadiusFactor / 70.f; //Magic number = old base setting
	float spacing = getGameSetting("MAP_SYSTEM_SPACING", 3000.f);
	bool hollow = getGameSetting("MAP_HOLLOW", 0) > 0.5f;
	setMakeOddities(getGameSetting("MAP_ODDITIES", 1.f) != 0.f);

	float minRad = 250.f;
	uint sysIndex = 0;

	if(sysCount >= 10) {
		minRad = makeQuasar(Glx, vector(0,0,0), sqrt(float(sysCount) / 50.f));
		++sysIndex;
	}

	if(hollow)
		minRad = maxRad = maxRad * 0.5f;
	
	for(; sysIndex < sysCount; ++sysIndex) {
		vector position = generateRandomVector(false, minRad, maxRad);

		makeRandomSystem(Glx, position, sysIndex, sysCount);
		updateProgress(sysIndex, sysCount);
	}
}

Planet@ setupHomeworld(System@ sys, Empire@ owner) {
	return setupStandardHomeworld(sys, owner);
}
