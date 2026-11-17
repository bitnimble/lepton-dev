package app.lepton.helper;

import android.app.Activity;
import android.graphics.Color;
import android.os.Bundle;
import android.util.TypedValue;
import android.view.Gravity;
import android.view.WindowInsets;
import android.view.WindowInsetsController;
import android.widget.LinearLayout;
import android.widget.ProgressBar;
import android.widget.TextView;

/** A full-screen spinner with a title and detail line, shown while the host sets Android up; the host ends it. */
public final class WaitActivity extends Activity {
    @Override
    protected void onCreate(Bundle saved) {
        super.onCreate(saved);
        LinearLayout page = new LinearLayout(this);
        page.setOrientation(LinearLayout.VERTICAL);
        page.setGravity(Gravity.CENTER);
        page.setBackgroundColor(Color.rgb(22, 30, 42));
        ProgressBar spinner = new ProgressBar(this, null, android.R.attr.progressBarStyleLarge);
        spinner.setIndeterminate(true);
        page.addView(spinner);
        page.addView(text(getIntent().getStringExtra("title"), 26, Color.WHITE));
        page.addView(text(getIntent().getStringExtra("detail"), 18, Color.rgb(154, 168, 184)));
        setContentView(page);
        WindowInsetsController insets = getWindow().getInsetsController();
        if (insets != null) insets.hide(WindowInsets.Type.systemBars());
    }

    @Override
    @SuppressWarnings("deprecation")
    public void onBackPressed() {
        // leaving would show the half-updated app behind
    }

    private TextView text(String value, int sp, int colour) {
        TextView view = new TextView(this);
        view.setText(value == null ? "" : value);
        view.setTextSize(TypedValue.COMPLEX_UNIT_SP, sp);
        view.setTextColor(colour);
        view.setGravity(Gravity.CENTER);
        view.setPadding(0, (int) (16 * getResources().getDisplayMetrics().density), 0, 0);
        return view;
    }
}
