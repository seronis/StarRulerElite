//SPHERE GAS CREATION
// This script generates a big sphere of gas

//GAS SETTINGS
//Multiplier to the sprite's size that determines the fade out distance
const float fadeOutFactor = 2.25f;

const float baseSize = 19000.f;

const float baseSpriteCount = 600.f;

const float endSizeOffset = 0.125f;

Color innerCol(20,255,255,255), outerCol(35,50,50,150);

//Called after the galaxy has formed
void createEnvironment(vector minBound, vector maxBound) {
	string@ dustSprite = "dust";
	float glxRadius = max(abs(min(minBound.x, minBound.z)), max(maxBound.x, maxBound.z));
	
	float spriteSizeMult = baseSize;
	float sizeCurve = 0.67f;
	
	uint maxSprites = clamp( int(getGameSetting("MAP_BASE_GAS_SPRITES", baseSpriteCount) * sqrt(glxRadius / 35000.f)), 1, int(getGameSetting("MAP_MAX_GAS_SPRITES", baseSpriteCount * 2.f)) );
	bool hollow = getGameSetting("MAP_HOLLOW", 0) > 0.5f;

	float maxRad = glxRadius;
	float minRad = hollow ? maxRad : 0.f;
	
	for (uint i = 0; i < maxSprites; ++i) {
		vector position = generateRandomVector(false, minRad, maxRad);

		float dist = position.getLength();

		float spriteSize = spriteSizeMult * pow(glxRadius / 35000.f, sizeCurve);

		Color spriteCol = outerCol.interpolate(innerCol, dist / glxRadius);
		
		position.normalize(dist);	
		createGalaxyGasSprite(dustSprite, spriteSize, position, spriteCol, spriteSize * fadeOutFactor);
	}
}
