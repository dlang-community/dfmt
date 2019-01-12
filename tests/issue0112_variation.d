unittest
{
	testScene = new Scene
	(
		longArgument, longArgument, longArgument, longArgument, longArgument, longArgument,
		 delegate(Scene scene)
		 {
			 import std.stdio;

			 if (!scene.alreadyEntered)
			 {
				 fwriteln("This is a test. This is a test. This is a test. This is a test. This is a test. Test12.");
				 auto p = cast(Portal)sceneManager.previousScene;
				 scene.destroyCurrentScript();
			 }
		 }
	);
}
