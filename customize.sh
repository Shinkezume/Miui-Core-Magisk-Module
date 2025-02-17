# space
ui_print " "

# log
if [ "$BOOTMODE" != true ]; then
  FILE=/sdcard/$MODID\_recovery.log
  ui_print "- Log will be saved at $FILE"
  exec 2>$FILE
  ui_print " "
fi

# run
. $MODPATH/function.sh

# info
MODVER=`grep_prop version $MODPATH/module.prop`
MODVERCODE=`grep_prop versionCode $MODPATH/module.prop`
ui_print " ID=$MODID"
ui_print " Version=$MODVER"
ui_print " VersionCode=$MODVERCODE"
if [ "$KSU" == true ]; then
  ui_print " KSUVersion=$KSU_VER"
  ui_print " KSUVersionCode=$KSU_VER_CODE"
  ui_print " KSUKernelVersionCode=$KSU_KERNEL_VER_CODE"
  sed -i 's|#k||g' $MODPATH/post-fs-data.sh
else
  ui_print " MagiskVersion=$MAGISK_VER"
  ui_print " MagiskVersionCode=$MAGISK_VER_CODE"
fi
ui_print " "

# bit
if [ "$IS64BIT" == true ]; then
  ui_print "- 64 bit"
else
  ui_print "- 32 bit"
  rm -rf `find $MODPATH -type d -name *64*`
fi
ui_print " "

# sdk
NUM=21
if [ "$API" -lt $NUM ]; then
  ui_print "! Unsupported SDK $API."
  ui_print "  You have to upgrade your Android version"
  ui_print "  at least SDK API $NUM to use this module."
  abort
else
  ui_print "- SDK $API"
  ui_print " "
fi

# recovery
mount_partitions_in_recovery

# magisk
magisk_setup

# path
SYSTEM=`realpath $MIRROR/system`
PRODUCT=`realpath $MIRROR/product`
VENDOR=`realpath $MIRROR/vendor`
SYSTEM_EXT=`realpath $MIRROR/system_ext`
if [ "$BOOTMODE" == true ]; then
  if [ ! -d $MIRROR/odm ]; then
    mount_odm_to_mirror
  fi
  if [ ! -d $MIRROR/my_product ]; then
    mount_my_product_to_mirror
  fi
fi
ODM=`realpath $MIRROR/odm`
MY_PRODUCT=`realpath $MIRROR/my_product`

# optionals
OPTIONALS=/sdcard/optionals.prop
if [ ! -f $OPTIONALS ]; then
  touch $OPTIONALS
fi

# sepolicy
FILE=$MODPATH/sepolicy.rule
DES=$MODPATH/sepolicy.pfsd
if [ "`grep_prop sepolicy.sh $OPTIONALS`" == 1 ]\
&& [ -f $FILE ]; then
  mv -f $FILE $DES
fi

# function
check_function() {
ui_print "- Checking"
ui_print "$NAME"
ui_print "  function at"
ui_print "$FILE"
ui_print "  Please wait..."
if ! grep -q $NAME $FILE; then
  ui_print "  Using legacy libraries"
  cp -rf $MODPATH/system_10/* $MODPATH/system
fi
ui_print " "
}

# check
NAME=_ZN7android23sp_report_stack_pointerEv
DES="$MODPATH/system/bin/shelld
      $MODPATH/system/lib/libexmedia.so
      $MODPATH/system/lib/libmiuiblur.so
      $MODPATH/system/lib/libshell.so
      $MODPATH/system/vendor/lib/libcdsprpc.so"
LISTS=`strings $DES | grep ^lib | grep .so\
        | sed -e 's|libshellservice.so||g' -e 's|libshell_jni.so||g'\
        -e 's|libexmedia.so||g' -e 's|libmiuiblur.so||g'\
        -e 's|libshell.so||g' -e 's|libcdsprpc.so||g'\
        -e 's|lib%s_skel.so||g'`
FILE=`for LIST in $LISTS; do echo $SYSTEM/lib/$LIST; done`
check_function
if [ "$IS64BIT" == true ]; then
  DES="$MODPATH/system/lib64/libexmedia.so
        $MODPATH/system/lib64/libmiuiblur.so
        $MODPATH/system/lib64/libshell.so
        $MODPATH/system/vendor/lib64/libcdsprpc.so"
  LISTS=`strings $DES | grep ^lib | grep .so\
          | sed -e 's|libexmedia.so||g' -e 's|libmiuiblur.so||g'\
          -e 's|libshell.so||g' -e 's|libcdsprpc.so||g'\
          -e 's|lib%s_skel.so||g'`
  FILE=`for LIST in $LISTS; do echo $SYSTEM/lib64/$LIST; done`
  check_function
fi
rm -rf $MODPATH/system_10

# extract
APP=miuisystem
ui_print "- Extracting..."
FILE=`find $MODPATH/system -type f -name $APP.apk`
DIR=$MODPATH/system/etc
DES=assets/*
unzip -d $TMPDIR -o $FILE $DES
cp -rf $TMPDIR/$DES $DIR
ui_print " "

# cleaning
ui_print "- Cleaning..."
PKGS=`cat $MODPATH/package.txt`
if [ "$BOOTMODE" == true ]; then
  for PKG in $PKGS; do
    RES=`pm uninstall $PKG 2>/dev/null`
  done
fi
rm -rf $MODPATH/unused
remove_sepolicy_rule
ui_print " "
# power save
FILE=$MODPATH/system/etc/sysconfig/*
if [ "`grep_prop power.save $OPTIONALS`" == 1 ]; then
  ui_print "- $MODNAME will not be allowed in power save."
  ui_print "  It may save your battery but decreasing $MODNAME performance."
  for PKG in $PKGS; do
    sed -i "s|<allow-in-power-save package=\"$PKG\"/>||g" $FILE
    sed -i "s|<allow-in-power-save package=\"$PKG\" />||g" $FILE
  done
  ui_print " "
fi

# function
conflict() {
for NAME in $NAMES; do
  DIR=/data/adb/modules_update/$NAME
  if [ -f $DIR/uninstall.sh ]; then
    sh $DIR/uninstall.sh
  fi
  rm -rf $DIR
  DIR=/data/adb/modules/$NAME
  rm -f $DIR/update
  touch $DIR/remove
  FILE=/data/adb/modules/$NAME/uninstall.sh
  if [ -f $FILE ]; then
    sh $FILE
    rm -f $FILE
  fi
  rm -rf /metadata/magisk/$NAME
  rm -rf /mnt/vendor/persist/magisk/$NAME
  rm -rf /persist/magisk/$NAME
  rm -rf /data/unencrypted/magisk/$NAME
  rm -rf /cache/magisk/$NAME
  rm -rf /cust/magisk/$NAME
done
}

# conflict
NAMES=MIUICore
conflict

# function
permissive_2() {
sed -i 's|#2||g' $MODPATH/post-fs-data.sh
}
permissive() {
FILE=/sys/fs/selinux/enforce
SELINUX=`cat $FILE`
if [ "$SELINUX" == 1 ]; then
  if ! setenforce 0; then
    echo 0 > $FILE
  fi
  SELINUX=`cat $FILE`
  if [ "$SELINUX" == 1 ]; then
    ui_print "  Your device can't be turned to Permissive state."
    ui_print "  Using Magisk Permissive mode instead."
    permissive_2
  else
    if ! setenforce 1; then
      echo 1 > $FILE
    fi
    sed -i 's|#1||g' $MODPATH/post-fs-data.sh
  fi
else
  sed -i 's|#1||g' $MODPATH/post-fs-data.sh
fi
}

# permissive
if [ "`grep_prop permissive.mode $OPTIONALS`" == 1 ]; then
  ui_print "- Using device Permissive mode."
  rm -f $MODPATH/sepolicy.rule
  permissive
  ui_print " "
elif [ "`grep_prop permissive.mode $OPTIONALS`" == 2 ]; then
  ui_print "- Using Magisk Permissive mode."
  rm -f $MODPATH/sepolicy.rule
  permissive_2
  ui_print " "
fi

# public
FILE=$MODPATH/post-fs-data.sh
if [ "`grep_prop miui.public $OPTIONALS`" != 0 ]; then
  sed -i 's|#patch_public_libraries_nopreload|patch_public_libraries_nopreload|g' $FILE
else
  ui_print "- Does not use public libraries nopreload mode"
  ui_print "  You will not be able to normal install Miui apps"
  ui_print " "
fi

# function
file_check_bin() {
for NAME in $NAMES; do
  FILE=`realpath $SYSTEM/*bin/$NAME`
  FILE2=`realpath $SYSTEM_EXT/*bin/$NAME`
  FILE3=`realpath $VENDOR/*bin/$NAME`
  if [ "$FILE" ] || [ "$FILE2" ] || [ "$FILE3" ]; then
    ui_print "- Detected $NAME"
    ui_print " "
    rm -f $MODPATH/system/bin/$NAME
    rm -f $MODPATH/system/vendor/bin/$NAME
  fi
done
}
file_check_system() {
for NAME in $NAMES; do
  if [ "$IS64BIT" == true ]; then
    FILE=$SYSTEM/lib64/$NAME
    FILE2=$SYSTEM_EXT/lib64/$NAME
    if [ -f $FILE ] || [ -f $FILE2 ]; then
      ui_print "- Detected $NAME 64"
      ui_print " "
      rm -f $MODPATH/system/lib64/$NAME
    fi
  fi
  FILE=$SYSTEM/lib/$NAME
  FILE2=$SYSTEM_EXT/lib/$NAME
  if [ -f $FILE ] || [ -f $FILE2 ]; then
    ui_print "- Detected $NAME"
    ui_print " "
    rm -f $MODPATH/system/lib/$NAME
  fi
done
}
file_check_vendor() {
for NAME in $NAMES; do
  if [ "$IS64BIT" == true ]; then
    FILE=$VENDOR/lib64/$NAME
    FILE2=$ODM/lib64/$NAME
    if [ -f $FILE ] || [ -f $FILE2 ]; then
      ui_print "- Detected $NAME 64"
      ui_print " "
      rm -f $MODPATH/system/vendor/lib64/$NAME
    fi
  fi
  FILE=$VENDOR/lib/$NAME
  FILE2=$ODM/lib/$NAME
  if [ -f $FILE ] || [ -f $FILE2 ]; then
    ui_print "- Detected $NAME"
    ui_print " "
    rm -f $MODPATH/system/vendor/lib/$NAME
  fi
done
}
file_check_vendor_grep() {
for NAME in $NAMES; do
  if [ "$IS64BIT" == true ]; then
    FILE=$VENDOR/lib64/$NAME
    FILE2=$ODM/lib64/$NAME
    SRC=$MODPATH/system/vendor/lib64/$NAME
    if [ -f $FILE ] || [ -f $FILE2 ]; then
      ui_print "- Detected $NAME 64"
      ui_print " "
      rm -f $SRC
    else
      TARGET="$VENDOR/lib64/$DES $ODM/lib64/$DES"
      if ! grep -q $NAME $TARGET; then
        rm -f $SRC
      fi
    fi
  fi
  FILE=$VENDOR/lib/$NAME
  FILE2=$ODM/lib/$NAME
  SRC=$MODPATH/system/vendor/lib/$NAME
  if [ -f $FILE ] || [ -f $FILE2 ]; then
    ui_print "- Detected $NAME"
    ui_print " "
    rm -f $SRC
  else
    TARGET="$VENDOR/lib/$DES $ODM/lib/$DES"
    if ! grep -q $NAME $TARGET; then
      rm -f $SRC
    fi
  fi
done
}

# check
NAMES=shelld
file_check_bin
NAMES=`ls $MODPATH/system/lib`
file_check_system
NAMES=`ls $MODPATH/system/vendor/lib`
file_check_vendor

# media
if [ ! -d /product/media ] && [ -d /system/media ]; then
  ui_print "- Using /system/media instead of /product/media"
  mv -f $MODPATH/system/product/media $MODPATH/system
  rm -rf $MODPATH/system/product
  ui_print " "
elif [ ! -d /product/media ] && [ ! -d /system/media ]; then
  ui_print "! /product/media & /system/media not found"
  ui_print " "
fi

# unmount
if [ "$BOOTMODE" == true ] && [ ! "$MAGISKPATH" ]; then
  unmount_mirror
fi
















