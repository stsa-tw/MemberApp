package tw.stsa.memberapp.feature.checkin

import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import tw.stsa.memberapp.R
import tw.stsa.memberapp.designsystem.BrandButton

/**
 * 確認報到, large.
 *
 * It used to be an ordinary brand button, the same as the ones around it, and a
 * worker reading the name and moving on scanned the next person without ever
 * admitting this one — the commonest way an arrival went unrecorded. Shared by
 * the scanner and the roster so the two doors look the same.
 */
@Composable
internal fun ConfirmCheckinButton(onClick: () -> Unit, enabled: Boolean) {
    BrandButton(onClick = onClick, enabled = enabled, large = true) {
        Icon(Icons.Filled.CheckCircle, contentDescription = null)
        Spacer(Modifier.size(8.dp))
        Text(
            text = stringResource(R.string.checkin_confirm),
            style = MaterialTheme.typography.titleMedium,
            fontWeight = FontWeight.Bold,
        )
    }
}
