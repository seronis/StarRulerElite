//spiral
//======
//Creates a spiral-arm like galaxy, with uniform distribution throughout the disc, with a bulge in the center

#include "/include/map_lib.as"
#include "/include/spiral_gas.as"

void makeMap(Galaxy@ Glx) {
	prepMap();
	
	uint sysCount = getGameSetting("SYSTEM_COUNT",150);
	float rad, theta;
	float maxRad = sqrt(sysCount) * getGameSetting("MAP_SYSTEM_SPACING", 3000.f) * orbitRadiusFactor / 70.f; //Magic number = old base setting
	float maxHgt = maxRad / 4.f;
	if(getGameSetting("MAP_FLATTEN", 0) == 1)
		maxHgt = 0;
	setMakeOddities(getGameSetting("MAP_ODDITIES", 1.f) != 0.f);

	float minRad = 250.f;
	
	uint sysIndex = 0;
	if(sysCount >= 50) {
		minRad = makeQuasar(Glx, vector(0,0,0), sqrt(float(sysCount) / 50.f)) + (12.f * orbitRadiusFactor);
		++sysIndex;
	}
	
	for(; sysIndex < sysCount; ++sysIndex) {
		theta = randomf(twoPi);
		rad = range(minRad, maxRad, pow(randomf(1.f),0.85f));
		
		vector position(rad * cos(theta), pow(1.f - (rad/maxRad), 2.f) * maxHgt * (randomf(1.f) - 0.5f), rad * sin(theta));
		
		makeRandomSystem(Glx, position, sysIndex, sysCount);
		updateProgress(sysIndex, sysCount);
	}
}

Planet@ setupHomeworld(System@ sys, Empire@ owner) {
	return setupStandardHomeworld(sys, owner);
}
