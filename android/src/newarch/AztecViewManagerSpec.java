package com.aztec;

import android.view.View;

import androidx.annotation.Nullable;

import com.facebook.react.uimanager.BaseViewManager;
import com.facebook.react.uimanager.LayoutShadowNode;
import com.facebook.react.uimanager.SimpleViewManager;
import com.facebook.react.uimanager.ViewManagerDelegate;
import com.facebook.react.viewmanagers.AztecViewManagerDelegate;
import com.facebook.react.viewmanagers.AztecViewManagerInterface;
//BaseViewManager<ReactAztecText, LayoutShadowNode>
public abstract class AztecViewManagerSpec<T extends View, C extends LayoutShadowNode> extends BaseViewManager<T, C> implements AztecViewManagerInterface<T> {
  private final ViewManagerDelegate<T> mDelegate;

  public AztecViewManagerSpec() {
    mDelegate = new AztecViewManagerDelegate(this);
  }

  @Nullable
  @Override
  protected ViewManagerDelegate<T> getDelegate() {
    return mDelegate;
  }
}
