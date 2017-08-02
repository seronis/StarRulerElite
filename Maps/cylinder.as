//cylinder
//========
//Creates a cylinder filled with systems

#include "/include/map_lib.as"
#include "/include/cylinder_gas.as"

void makeMap(Galaxy@ Glx) {
	prepMap();
	
	uint sysCount = getGameSetting("SYSTEM_COUNT",150);
	float rad, theta;
	float maxRad = sqrt(sysCount) * getGameSetting("MAP_SYSTEM_SPACING", 3000.f) * orbitRadiusFactor / 140.f; //Magic number = old base setting
	setMakeOddities(getGameSetting("MAP_ODDITIES", 1.f) != 0.f);
	bool hollow = getGameSetting("MAP_HOLLOW", 0) > 0.5f;

	float minRad = 250.f;
	rad = maxRad * 0.5f;
	
	for(uint sysIndex = 0; sysIndex < sysCount; ++sysIndex) {
		theta = randomf(twoPi);
		if (!hollow)
			rad = range(minRad, maxRad * 0.5f, pow(randomf(1.f),0.85f));
		
		vector position = vector(randomf(-0.5f, 0.5f)*maxRad, rad * cos(theta), rad * sin(theta));
		
		makeRandomSystem(Glx, position, sysIndex, sysCount);
		updateProgress(sysIndex, sysCount);
	}
}

Planet@ setupHomeworld(System@ sys, Empire@ owner) {
	return setupStandardHomeworld(sys, owner);
}
