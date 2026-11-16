package lepton.abitest;

import android.app.Activity;
import android.os.Bundle;
import android.os.Process;
import android.util.Log;
import java.io.FileWriter;

// Loads an ARM64 .so to check whether this process gets native-bridge translation.
public class MainActivity extends Activity {
    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        StringBuilder out = new StringBuilder();
        out.append("is64Bit=").append(Process.is64Bit()).append('\n');
        out.append("abi=").append(android.os.Build.SUPPORTED_ABIS.length > 0 ? android.os.Build.SUPPORTED_ABIS[0] : "?").append('\n');
        String lib = getIntent().getStringExtra("lib");
        try {
            System.load(lib);
            out.append("LOAD_OK ").append(lib).append('\n');
        } catch (Throwable t) {
            out.append("LOAD_FAIL ").append(t).append('\n');
        }
        String result = out.toString();
        Log.i("LeptonAbiTest", result);
        try (FileWriter w = new FileWriter("/data/local/tmp/abitest-result.txt")) {
            w.write(result);
        } catch (Throwable ignored) {
        }
        finish();
    }
}
