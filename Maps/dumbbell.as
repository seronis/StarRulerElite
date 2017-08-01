//dumbbell
//=====
//Creates two spheres joined by a cylinder

#include "/include/map_lib.as"
#include "/include/dumbbell_gas.as"

void makeMap(Galaxy@ Glx) {
	prepMap();
	
	uint sysCount = getGameSetting("SYSTEM_COUNT",150);
	float maxRad = sqrt(sysCount) * getGameSetting("MAP_SYSTEM_SPACING", 3000.f) * orbitRadiusFactor / 70.f; //Magic number = old base setting
	setMakeOddities(getGameSetting("MAP_ODDITIES", 1.f) != 0.f);
	bool flatten = getGameSetting("MAP_FLATTEN", 0) > 0.5f;

	float minRad = 250.f;

	uint cntOne = sysCount / 5 * 2;
	uint cntTwo = cntOne * 2;

	vector baseOne = vector(maxRad, 0, 0);
	vector baseTwo = vector(-maxRad, 0, 0);
	
	for(uint sysIndex = 0; sysIndex < sysCount; ++sysIndex) {
		vector position;
		{
			if(sysIndex < cntOne) {
				position = baseOne + generateRandomVector(flatten, minRad, maxRad * 0.5f);
			}
			else if (sysIndex < cntTwo) {
				position = baseTwo + generateRandomVector(flatten, minRad, maxRad * 0.5f);
			}
			else {
				float theta = randomf(twoPi);
				float radius = range(minRad, maxRad * 0.2f, pow(randomf(1.f),0.85f));

				position = vector(randomf(-0.6f, 0.6f)*maxRad, 
					flatten ? 0.f : radius * cos(theta), radius * sin(theta));
			}
		}
		
		makeRandomSystem(Glx, position, sysIndex, sysCount);
		updateProgress(sysIndex, sysCount);
	}
}

Planet@ setupHomeworld(System@ sys, Empire@ owner) {
	return setupStandardHomeworld(sys, owner);
}
