INSTALL_DIR=/usr/local/bin
SOURCE=ts.py
SOURCE_BAK=ts.py.bak
TARGET=pyts
TARGET_LIB=__pyscripts__

$(TARGET).skel: $(SOURCE)
	@mkdir -p $(INSTALL_DIR)/$(TARGET_LIB)
	@cp $(SOURCE) ${SOURCE_BAK}
	@cp $(SOURCE) $(INSTALL_DIR)/$(TARGET_LIB)/$(TARGET)
	@echo "Converting $(SOURCE) to shell script"
	@echo "#!/usr/bin/zsh" > $(TARGET).skel
	@echo "(" >> $(TARGET).skel
	@echo "exec python $(INSTALL_DIR)/$(TARGET_LIB)/$(TARGET) \$$@ && echo &" >> $(TARGET).skel
	@echo ") 2>/dev/null" >> $(TARGET).skel
	@mv $(TARGET).skel $(TARGET)
	@chmod 775 $(TARGET)

clean:
	@rm -f $(TARGET)
	@rm -f $(TARGET).skel

install: $(TARGET).skel
	@echo "Installing $(TARGET) to $(INSTALL_DIR)"
	@cp $(TARGET) $(INSTALL_DIR)
