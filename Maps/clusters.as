//sphere
//======
//Creates a sphere with systems positioned at random inside it

#include "/include/map_lib.as"

//Multiplier to the sprite's size that determines the fade out distance
const float fadeOutFactor = 2.25f;

const float baseSize = 12000.f;

const float baseSpriteCount = 600.f;

const float endSizeOffset = 0.125f;

Color innerCol(20,255,255,255), outerCol(35,50,50,150);

vector[] clusters;
float[] clusterRadius;

void makeMap(Galaxy@ Glx) {
	prepMap();
	
	uint sysCount = getGameSetting("SYSTEM_COUNT",150);
	float maxRad = sqrt(sysCount) * getGameSetting("MAP_SYSTEM_SPACING", 3000.f) * orbitRadiusFactor / 30.f; //Magic number = old base setting
	float spacing = getGameSetting("MAP_SYSTEM_SPACING", 3000.f);
	bool flatten = getGameSetting("MAP_FLATTEN", 0) > 0.5f;
	bool clusterFlatten = getGameSetting("CLUSTER_FLATTEN", 0) > 0.5f;
	setMakeOddities(getGameSetting("MAP_ODDITIES", 1.f) != 0.f);

	uint clSize = getGameSetting("MAP_CLUSTER_SIZE", 10);
	float clVar = getGameSetting("MAP_CLUSTER_VARIANCE", 0.2f);

	float minRad = 250.f;
	
	uint inCluster = 0;
	float clusterRad = 0.f;
	vector basePosition, position;

	for(uint sysIndex = 0; sysIndex < sysCount; ++sysIndex) {
		if (inCluster == 0) {
			basePosition = generateRandomVector(flatten, minRad, maxRad);
			inCluster = round(float(clSize) * (1.f - clVar + randomf(clVar*2.f)));
			clusterRad = spacing * sqrt(inCluster) * 2.f;

			uint num = clusters.length();

			clusters.resize(num+1);
			clusterRadius.resize(num+1);

			clusters[num] = basePosition;
			clusterRadius[num] = clusterRad;
		}

		position = basePosition + generateRandomVector(clusterFlatten, 0, clusterRad);

		makeRandomSystem(Glx, position, sysIndex, sysCount);
		updateProgress(sysIndex, sysCount);
		--inCluster;
	}
}

Planet@ setupHomeworld(System@ sys, Empire@ owner) {
	return setupStandardHomeworld(sys, owner);
}

void createEnvironment(vector minBound, vector maxBound) {
	string@ dustSprite = "dust";
	float spriteSizeMult = baseSize;
	float sizeCurve = 0.67f;

	bool flatten = getGameSetting("MAP_FLATTEN", 0) > 0.5f;
	bool clusterFlatten = getGameSetting("CLUSTER_FLATTEN", 0) > 0.5f;
	float glxRadius = max(abs(min(minBound.x, minBound.z)), max(maxBound.x, maxBound.z));
	uint maxSprites = clamp( int(getGameSetting("MAP_BASE_GAS_SPRITES", baseSpriteCount) * sqrt(glxRadius / 35000.f)), 1, int(getGameSetting("MAP_MAX_GAS_SPRITES", baseSpriteCount * 2.f)) );

	uint numCluster = clusters.length();
	uint sprCluster = maxSprites / numCluster;

	for (uint i = 0; i < numCluster; ++i) {
		vector basePosition = clusters[i];
		float clusterRad = clusterRadius[i];

		for (uint j = 0; j < sprCluster; ++j) {
			vector position = generateRandomVector(clusterFlatten, 0, clusterRad);
			float dist = position.getLength();
			float spriteSize = spriteSizeMult * 2.f * pow(clusterRad / 35000.f, sizeCurve);
			Color spriteCol = outerCol.interpolate(innerCol, dist / clusterRad);

			position += basePosition;

			position.normalize(position.getLength());	
			createGalaxyGasSprite(dustSprite, spriteSize, position, spriteCol, spriteSize * fadeOutFactor);
		}
	}
}
