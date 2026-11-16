package lepton.mantisbuddy;

import android.app.Instrumentation;
import android.os.Bundle;
import android.util.Log;
import dalvik.system.DexClassLoader;
import java.lang.reflect.Field;
import java.util.Properties;

public class BuddyHost extends Instrumentation {
    private static final String TAG = "LeptonMantisBuddy";
    private static final String INJECT_SERVICE = "app.mantispro.injector.injection.InjectServiceKt";

    private String bundleDir;
    private String operation;

    @Override
    public void onCreate(Bundle arguments) {
        super.onCreate(arguments);
        bundleDir = arguments.getString("bundle");
        operation = arguments.getString("operation", "lepton");
        start();
    }

    @Override
    public void onStart() {
        try {
            String dex = bundleDir + "/mantis.dex";
            // The daemon derives its bundle and library path from java.class.path, which libcore won't let setProperty change.
            Field field = System.class.getDeclaredField("unchangeableProps");
            field.setAccessible(true);
            ((Properties) field.get(null)).setProperty("java.class.path", dex);
            System.setProperty("mantis.operation", operation);
            // Boot parent: the target apk bundles its own, incompatible kotlin.
            // ndk_translation only bridges a namespace whose search path contains "/lib/arm"; the entry needn't exist.
            String libraryPath = bundleDir + ":/system/lib/arm64";
            ClassLoader loader = new DexClassLoader(dex, null, libraryPath, ClassLoader.getSystemClassLoader().getParent());
            Log.i(TAG, "starting " + dex);
            loader.loadClass(INJECT_SERVICE).getMethod("main", String[].class).invoke(null, (Object) new String[0]);
            Log.w(TAG, "daemon returned");
        } catch (Throwable t) {
            Log.e(TAG, "daemon failed", t);
        }
        Bundle result = new Bundle();
        result.putString("stopped", bundleDir);
        finish(1, result);
    }
}
