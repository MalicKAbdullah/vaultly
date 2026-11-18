package dev.abdullah.vaultkey.fill

import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import android.service.autofill.Dataset
import android.view.autofill.AutofillId
import android.view.autofill.AutofillValue
import android.widget.RemoteViews
import androidx.annotation.RequiresApi
import dev.abdullah.vaultkey.R

/** Datasets for the system autofill UI. */
@RequiresApi(Build.VERSION_CODES.O)
object DatasetFactory {

    fun presentation(context: Context, label: String): RemoteViews =
        RemoteViews(context.packageName, R.layout.vaultly_autofill_item).apply {
            setTextViewText(R.id.vaultly_autofill_text, label)
        }

    /**
     * A dataset that holds no values: tapping it runs [authentication], whose
     * result replaces it. Every fillable id is registered so the system
     * applies the result to all of them.
     */
    @Suppress("DEPRECATION")
    fun locked(
        context: Context,
        label: String,
        ids: List<AutofillId>,
        authentication: PendingIntent,
    ): Dataset {
        val presentation = presentation(context, label)
        return Dataset.Builder(presentation).apply {
            ids.forEach { setValue(it, null, presentation) }
            setAuthentication(authentication.intentSender)
        }.build()
    }

    /** The dataset the authentication activity returns: [values] by field. */
    @Suppress("DEPRECATION")
    fun filled(context: Context, label: String, values: Map<AutofillId, String>): Dataset {
        val presentation = presentation(context, label)
        return Dataset.Builder(presentation).apply {
            values.forEach { (id, text) -> setValue(id, AutofillValue.forText(text), presentation) }
        }.build()
    }

    /** Authentication intents must be mutable: the system adds the fill context. */
    fun authIntent(context: Context, requestCode: Int, intent: Intent): PendingIntent {
        var flags = PendingIntent.FLAG_CANCEL_CURRENT
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) flags = flags or PendingIntent.FLAG_MUTABLE
        return PendingIntent.getActivity(context, requestCode, intent, flags)
    }
}
